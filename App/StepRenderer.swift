import AppKit
import SnapCore

/// Shared native metrics keep marker labels and borders identical on canvas/export.
enum StepRenderer {
    static func draw(_ a: Annotation, in context: CGContext) {
        let style = a.resolvedStepAppearance, rect = StepGeometry.body(a), path = StepGeometry.path(a)
        context.saveGState(); context.setAlpha(a.opacity)
        if style.shadow { context.setShadow(offset: CGSize(width: 0, height: 2), blur: 5, color: NSColor.black.withAlphaComponent(0.25).cgColor) }
        if style.shape != .ring {
            context.setFillColor(nsColor(fromHex: a.colorHex).cgColor)
            context.addPath(path); context.fillPath()
        }
        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.setStrokeColor(nsColor(fromHex: style.shape == .ring ? a.colorHex : style.borderColorHex).cgColor)
        context.setLineWidth(style.shape == .ring ? max(2, style.borderWidth) : style.borderWidth)
        context.setLineJoin(.round)
        if style.shape == .ring || style.borderWidth > 0 { context.addPath(path); context.strokePath() }
        let weight: NSFont.Weight = (style.bold ?? true) ? .bold : .regular
        let baseFont = style.fontFamily == "System" ? NSFont.systemFont(ofSize: style.fontSize, weight: weight) : (NSFont(name: style.fontFamily, size: style.fontSize) ?? NSFont.systemFont(ofSize: style.fontSize, weight: weight))
        let initial = (style.bold ?? true) ? NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask) : baseFont
        let label = a.stepLabel as NSString
        let measured = label.size(withAttributes: [.font: initial])
        let available = max(8, rect.width - CGFloat(style.padding * 2 + style.borderWidth))
        let scale = min(1, min(available / max(1, measured.width), available / max(1, measured.height)))
        let font = NSFont(descriptor: initial.fontDescriptor, size: max(8, initial.pointSize * scale)) ?? initial
        let color = style.textColorHex.map { nsColor(fromHex: $0) } ?? (style.shape == .ring ? nsColor(fromHex: a.colorHex) : .white)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = label.size(withAttributes: attributes)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        label.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState(); context.restoreGState()
    }
}
