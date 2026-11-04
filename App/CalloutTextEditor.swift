import AppKit
import SwiftUI
import SnapCore

/// Inline native input. Focus is requested once on window attachment, never on redraw.
struct CalloutTextEditor: NSViewRepresentable {
    let annotation: Annotation
    let scale: CGFloat
    let onChange: (String) -> Void
    let onCommit: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> Input {
        let view = Input()
        view.setAccessibilityLabel("Callout text")
        view.isRichText = false
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = false
        view.allowsUndo = true
        view.string = annotation.text
        view.delegate = context.coordinator
        configure(view)
        return view
    }
    func updateNSView(_ view: Input, context: Context) {
        context.coordinator.parent = self
        configure(view)
        // Never replace the input string during composition or reset the selection on redraw.
    }
    private func configure(_ view: Input) {
        let font = CalloutTextLayout.font(annotation)
        view.font = NSFont(descriptor: font.fontDescriptor, size: font.pointSize * scale)
        let attributes = CalloutTextLayout.attributes(annotation)
        view.defaultParagraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle
        if let paragraph = view.defaultParagraphStyle, view.alignment != paragraph.alignment {
            view.alignment = paragraph.alignment
        }
        view.textColor = nsColor(fromHex: annotation.resolvedCalloutAppearance.textColorHex)
        view.commit = onCommit; view.cancel = onCancel
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CalloutTextEditor
        init(_ parent: CalloutTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.onChange(view.string)
        }
    }
    final class Input: NSTextView {
        private let localUndo = UndoManager()
        override var undoManager: UndoManager? { localUndo }
        var commit: () -> Void = {}
        var cancel: () -> Void = {}
        private var requestedFocus = false
        private var finished = false
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, !requestedFocus else { return }
            requestedFocus = true
            window.makeFirstResponder(self)
            setSelectedRange(NSRange(location: (string as NSString).length, length: 0))
        }
        override func keyDown(with event: NSEvent) {
            if (event.keyCode == 36 || event.keyCode == 76) && event.modifierFlags.contains(.command) {
                finish(); return
            }
            super.keyDown(with: event)
        }
        override func cancelOperation(_ sender: Any?) {
            guard !finished else { return }
            finished = true; cancel()
        }
        override func insertTab(_ sender: Any?) { finish() }
        override func resignFirstResponder() -> Bool {
            let result = super.resignFirstResponder()
            if result { finish() }
            return result
        }
        private func finish() {
            guard !finished else { return }
            finished = true; commit()
        }
    }
}
