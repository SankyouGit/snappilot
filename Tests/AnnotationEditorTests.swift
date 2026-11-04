import XCTest
import AppKit
import SwiftUI
import SnapCore
@testable import Snappilot

final class AnnotationEditorTests: XCTestCase {
    @MainActor
    func testImmediateNativeFocusAndTyping() async throws {
        var appearance = CalloutAppearance(); appearance.shape = .blockArrow
        let a = Annotation(id: 1, tool: .callout, start: CGPoint(x: 20, y: 20), end: CGPoint(x: 240, y: 100),
            pointerTip: CGPoint(x: 340, y: 60), calloutAppearance: appearance)
        var text = "", committed = false
        let root = CalloutTextEditor(annotation: a, scale: 1, onChange: { text = $0 },
            onCommit: { committed = true }, onCancel: {})
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 300, height: 100),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = NSHostingView(rootView: root.frame(width: 280, height: 80))
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(150))
        let input = try XCTUnwrap(window.firstResponder as? NSTextView, "Native input must own focus without a second click")
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "a",
            charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0))
        window.sendEvent(event)
        XCTAssertEqual(input.string, "a", "The first key must reach the native text editor")
        XCTAssertEqual(text, "a")
        input.insertText(" step", replacementRange: input.selectedRange())
        XCTAssertEqual(text, "a step")
        let commandReturn = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 1, windowNumber: window.windowNumber, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        window.sendEvent(commandReturn)
        XCTAssertTrue(committed)
    }

    @MainActor
    func testTextSessionUndoCancelAndReopen() async throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 800, height: 500, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let model = EditorModel(base: try XCTUnwrap(context.makeImage()), appState: nil)
        let id = model.commit(tool: .callout, start: CGPoint(x: 50, y: 100), end: CGPoint(x: 450, y: 120))
        XCTAssertEqual(model.doc.items.count, 1)
        XCTAssertEqual(model.editingTextID, id)
        model.updateText(id: id, "Click here")
        model.finishTextEditing()
        XCTAssertEqual(model.selectedID, id)
        try await Task.sleep(for: .milliseconds(50)) // close the native event undo group
        model.beginTextEditing(id: id)
        model.updateText(id: id, "Changed")
        model.finishTextEditing(cancel: true)
        XCTAssertEqual(model.doc.items[0].text, "Click here")
        model.beginTextEditing(id: id)
        model.updateText(id: id, "Edited")
        model.finishTextEditing()
        try await Task.sleep(for: .milliseconds(50))
        model.undo()
        XCTAssertEqual(model.doc.items[0].text, "Click here")
        model.redo()
        XCTAssertEqual(model.doc.items[0].text, "Edited")
        let count = model.doc.items.count
        _ = model.commit(tool: .callout, start: CGPoint(x: 100, y: 200), end: CGPoint(x: 500, y: 240))
        model.finishTextEditing(cancel: true)
        XCTAssertEqual(model.doc.items.count, count)
    }

    @MainActor
    func testShapeTextMetricsAndExportAttachment() async throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 1000, height: 600, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 1000, height: 600))
        let base = try XCTUnwrap(context.makeImage())
        for shape in CalloutShape.availableCases {
            var appearance = CalloutAppearance(); appearance.shape = shape
            appearance.rotationDegrees = 20; appearance.fontSize = 28; appearance.alignment = .center
            var doc = AnnotationDocument()
            let seed = doc.add(.callout, start: CGPoint(x: 200, y: 180), end: CGPoint(x: 480, y: 300), text: "Click here\nto save")
            doc.update(id: seed.id) {
                $0.calloutAppearance = appearance; $0.pointerTip = CGPoint(x: 700, y: 100)
                $0 = CalloutTextLayout.fitted($0)
            }
            let a = doc.items[0], rect = CalloutTextLayout.textRect(a)
            XCTAssertGreaterThanOrEqual(rect.height + 1, CalloutTextLayout.measuredHeight(a, width: rect.width), shape.title)
            let image = AnnotationRenderer.flatten(base: base, doc: doc)
            XCTAssertEqual(image.width, 1000); XCTAssertEqual(image.height, 600)
            let attachment = XCTAttachment(image: NSImage(cgImage: image, size: NSSize(width: 1000, height: 600)))
            attachment.name = shape.title; attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
