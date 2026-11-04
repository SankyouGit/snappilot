import AppKit
import SnapCore

/// Shared document-space typography for canvas, text input and raster output.
enum CalloutTextLayout {
    static func font(_ a: Annotation) -> NSFont {
        let style = a.resolvedCalloutAppearance
        let size: CGFloat
        if style.shape == .blockArrow && (style.blockArrowAutoTextSize ?? true) {
            let geometry = BlockArrowGeometry(a)
            let proportional = min(geometry.body.width * 0.14, geometry.halfWidth * 0.84)
            size = max(CGFloat(style.fontSize), min(96, max(28, proportional)))
        } else { size = CGFloat(style.fontSize) }
        let weight: NSFont.Weight = style.bold ? .semibold : .regular
        if style.fontFamily != "System", let font = NSFont(name: style.fontFamily, size: size) {
            return style.bold ? NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) : font
        }
        return .systemFont(ofSize: size, weight: weight)
    }
    static func attributes(_ a: Annotation) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        switch a.resolvedCalloutAppearance.alignment {
        case .left: paragraph.alignment = .left
        case .center: paragraph.alignment = .center
        case .right: paragraph.alignment = .right
        }
        return [.font: font(a), .foregroundColor: nsColor(fromHex: a.resolvedCalloutAppearance.textColorHex), .paragraphStyle: paragraph]
    }
    static func textInset(_ a: Annotation) -> CGFloat {
        let style = a.resolvedCalloutAppearance
        let r = CalloutGeometry.body(a)
        let radius = (style.shape == .rectangle || style.shape == .blockArrow) ? 0 : min(CGFloat(style.cornerRadius), min(r.width, r.height) / 2)
        return max(CGFloat(style.padding + style.borderWidth / 2), radius * 0.293)
    }
    static func measuredHeight(_ a: Annotation, width: CGFloat) -> CGFloat {
        let content = a.text.isEmpty ? " " : a.text
        let string = content.hasSuffix("\n") ? content + " " : content
        return ceil((string as NSString).boundingRect(
            with: NSSize(width: max(1, width), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes(a)).height)
    }
    static func rotation(_ a: Annotation) -> CGFloat {
        (a.resolvedCalloutAppearance.shape == .blockArrow ? BlockArrowGeometry(a).textAngle : 0) + CalloutGeometry.rotation(a)
    }
    static func availableTextWidth(_ a: Annotation) -> CGFloat {
        let width = a.resolvedCalloutAppearance.shape == .blockArrow ? BlockArrowGeometry(a).labelWidth : CalloutGeometry.textBody(a).width
        return max(20, width - textInset(a) * 2)
    }
    static func textRect(_ a: Annotation) -> CGRect {
        let padding = textInset(a)
        var rect = CalloutGeometry.textBody(a).insetBy(dx: padding, dy: padding)
        if a.resolvedCalloutAppearance.shape == .blockArrow {
            let geometry = BlockArrowGeometry(a)
            let shift = geometry.textOffset
            rect = rect.offsetBy(dx: shift.dx, dy: shift.dy)
            let width = availableTextWidth(a)
            rect.origin.x += (rect.width - width) / 2
            rect.size.width = width
            let height = min(rect.height, measuredHeight(a, width: rect.width))
            rect.origin.y += (rect.height - height) / 2
            rect.size.height = height
        }
        let center = CalloutGeometry.rotate(CGPoint(x: rect.midX, y: rect.midY), on: a)
        rect.origin = CGPoint(x: center.x - rect.width / 2, y: center.y - rect.height / 2)
        return rect
    }
    static func fitted(_ a: Annotation) -> Annotation {
        guard a.resolvedCalloutAppearance.shape == .blockArrow else { return fittedOnce(a) }
        var out = a
        for _ in 0..<10 {
            let next = fittedOnce(out)
            if next == out { break }
            out = next
        }
        return out
    }
    private static func fittedOnce(_ a: Annotation) -> Annotation {
        var out = a
        let r = CalloutGeometry.body(a)
        if a.isModernCallout && a.resolvedCalloutAppearance.shape.hasPointer && out.pointerTip == nil {
            out.pointerTip = CGPoint(x: r.maxX + 60, y: r.midY)
        }
        let padding = textInset(a)
        let width = availableTextWidth(a)
        let measured = (((a.text.isEmpty ? " " : a.text) + "\n") as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes(a))
        out.start = r.origin
        let block = a.resolvedCalloutAppearance.shape == .blockArrow
        let height = block ? measuredHeight(a, width: width) : ceil(measured.height)
        let core = CalloutGeometry.textBody(a)
        let xRatio = max(0.1, core.width / max(1, r.width)), yRatio = max(0.1, core.height / max(1, r.height))
        out.end = CGPoint(x: r.minX + max((80 + padding * 2) / xRatio, r.width),
                          y: r.minY + max(r.height, (height + padding * 2) / yRatio))
        if block {
            var style = out.resolvedCalloutAppearance
            let geometry = BlockArrowGeometry(out)
            let minimum = geometry.minimumShaftScale(textWidth: width, textHeight: height, padding: padding)
            style.blockArrowShaftScale = max(style.blockArrowShaftScale ?? 1, minimum)
            out.calloutAppearance = style.normalized()
        }
        if CalloutGeometry.rotation(a) != 0 {
            let targetFrame = out
            out.pointerTip = a.pointerTip.map { CalloutGeometry.rotate(CalloutGeometry.rotate($0, on: a), on: targetFrame, inverse: true) }
            out.additionalPointerTips = a.additionalPointerTips?.map { CalloutGeometry.rotate(CalloutGeometry.rotate($0, on: a), on: targetFrame, inverse: true) }
        }
        return out
    }
    /// Context is top-left, in image pixels; used by both canvas and export.
    static func draw(_ a: Annotation, in context: CGContext, showText: Bool = true) {
        context.saveGState()
        context.setAlpha(a.opacity)
        let style = a.resolvedCalloutAppearance
        let path = CalloutGeometry.path(a)
        if style.shadow {
            context.setShadow(offset: CGSize(width: 0, height: 3), blur: 6,
                              color: NSColor.black.withAlphaComponent(0.22).cgColor)
        }
        context.setFillColor(nsColor(fromHex: a.colorHex).cgColor)
        context.addPath(path); context.fillPath()
        context.setShadow(offset: .zero, blur: 0, color: nil)
        if style.borderWidth > 0 {
            context.setStrokeColor(nsColor(fromHex: style.borderColorHex).cgColor)
            context.setLineWidth(style.borderWidth)
            context.setLineJoin(.round)
            context.setLineDash(phase: 0, lengths: a.lineStyle.dashPattern(width: style.borderWidth).map { CGFloat($0) })
            context.addPath(path); context.strokePath()
        }
        if showText && !a.text.isEmpty {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            let rect = textRect(a)
            context.saveGState()
            context.translateBy(x: rect.midX, y: rect.midY)
            context.rotate(by: rotation(a))
            (a.text as NSString).draw(with: CGRect(x: -rect.width / 2, y: -rect.height / 2, width: rect.width, height: rect.height),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes(a))
            context.restoreGState()
            NSGraphicsContext.restoreGraphicsState()
        }
        context.restoreGState()
    }
}
