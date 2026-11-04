import CoreGraphics

/// Text Arrow geometry in image pixels. Legacy callouts never enter this path.
public enum CalloutGeometry {
    public static let padding: CGFloat = 12
    public static func body(_ a: Annotation) -> CGRect { selectionRect(from: a.start, to: a.end) }
    public static func bounds(_ a: Annotation) -> CGRect {
        guard a.isModernCallout else { return body(a) }
        let style = a.resolvedCalloutAppearance
        var result = path(a).boundingBoxOfPath.union(body(a))
        if style.shape.hasPointer, let tip = a.pointerTip {
            result = result.union(CGRect(x: tip.x - 1, y: tip.y - 1, width: 2, height: 2))
        }
        let overflow = CGFloat(style.borderWidth / 2 + (style.shadow ? 15 : 0))
        return result.insetBy(dx: -overflow, dy: -overflow)
    }
    public static func create(_ a: Annotation, target: CGPoint) -> Annotation {
        var out = a
        if a.resolvedCalloutAppearance.shape != .arrow && a.resolvedCalloutAppearance.shape != .blockArrow {
            let drawn = selectionRect(from: a.start, to: target)
            if drawn.width >= 104 && drawn.height >= 48 {
                out.start = drawn.origin
                out.end = CGPoint(x: drawn.maxX, y: drawn.maxY)
            } else { out.end = CGPoint(x: a.start.x + 220, y: a.start.y + 72) }
        } else { out.end = CGPoint(x: a.start.x + 220, y: a.start.y + 72) }
        let r = body(out)
        out.pointerTip = r.insetBy(dx: -20, dy: -20).contains(target)
            ? CGPoint(x: r.maxX + 60, y: r.midY) : target
        return out
    }
    /// A rounded text body with a slim, direction-aligned shaft and crisp arrowhead.
    /// Keeping text horizontal preserves native editing when the target changes direction.
    public static func path(_ a: Annotation) -> CGPath {
        let r = body(a), p = CGMutablePath()
        let appearance = a.resolvedCalloutAppearance
        if !appearance.shape.hasPointer || a.pointerTip == nil {
            let radius: CGFloat = appearance.shape == .rectangle ? 0 : CGFloat(appearance.cornerRadius)
            return CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
        }
        guard let tip = a.pointerTip else { return CGPath(rect: r, transform: nil) }
        if appearance.shape == .blockArrow { return BlockArrowGeometry(a).path }
        let corners = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                       CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
        let dx = tip.x - r.midX, dy = tip.y - r.midY
        let side = abs(dx) / max(1, r.width) > abs(dy) / max(1, r.height)
            ? (dx > 0 ? 1 : 3) : (dy > 0 ? 2 : 0)
        var vertices = [corners[0]]
        for i in 0..<4 {
            let v = corners[i], w = corners[(i + 1) % 4]
            if i == side && !r.contains(tip) {
                let edgeLength = hypot(w.x - v.x, w.y - v.y)
                let ux = (w.x - v.x) / max(1, edgeLength)
                let uy = (w.y - v.y) / max(1, edgeLength)
                let normalX = uy, normalY = -ux
                let nominalHalf = max(3, min(8, min(r.width, r.height) * 0.09)) * CGFloat(appearance.pointerScale)
                // Intersect the center-to-target ray with the chosen edge, then keep
                // the opening clear of the rounded corners. Never snap to edge center.
                let ratio = i == 1 || i == 3
                    ? r.width / (2 * max(0.001, abs(dx)))
                    : r.height / (2 * max(0.001, abs(dy)))
                let intersection = CGPoint(x: r.midX + dx * ratio, y: r.midY + dy * ratio)
                let corner = min(CGFloat(appearance.cornerRadius), edgeLength / 4)
                let margin = min(edgeLength / 2, corner + nominalHalf * 2)
                let projected = (intersection.x - v.x) * ux + (intersection.y - v.y) * uy
                let offset = min(edgeLength - margin, max(margin, projected))
                let anchor = CGPoint(x: v.x + ux * offset, y: v.y + uy * offset)
                let distance = hypot(tip.x - anchor.x, tip.y - anchor.y)
                let directionX = (tip.x - anchor.x) / max(0.001, distance)
                let directionY = (tip.y - anchor.y) / max(0.001, distance)
                // Match the edge's traversal so this remains one non-crossing outline.
                var perpendicularX = -directionY, perpendicularY = directionX
                if perpendicularX * ux + perpendicularY * uy < 0 {
                    perpendicularX = -perpendicularX; perpendicularY = -perpendicularY
                }
                let shaftHalf = min(nominalHalf, distance * 0.16)
                let headHalf = shaftHalf * 2.4
                let depth = min(headHalf * 1.7, distance * 0.5)
                let base = CGPoint(x: tip.x - directionX * depth, y: tip.y - directionY * depth)
                let incidence = max(0.15, directionX * normalX + directionY * normalY)
                let openingHalf = min(shaftHalf / incidence, max(0, min(offset, edgeLength - offset) - corner))
                func shoulder(_ half: CGFloat) -> CGPoint {
                    CGPoint(x: base.x + perpendicularX * half, y: base.y + perpendicularY * half)
                }
                vertices.append(CGPoint(x: anchor.x - ux * openingHalf, y: anchor.y - uy * openingHalf))
                if appearance.shape == .arrow {
                    vertices.append(shoulder(-shaftHalf))
                    vertices.append(shoulder(-headHalf))
                }
                vertices.append(tip)
                if appearance.shape == .arrow {
                    vertices.append(shoulder(headHalf))
                    vertices.append(shoulder(shaftHalf))
                }
                vertices.append(CGPoint(x: anchor.x + ux * openingHalf, y: anchor.y + uy * openingHalf))
            }
            vertices.append(w)
        }
        vertices.removeLast() // closing corner is represented by the first vertex
        for i in vertices.indices {
            let v = vertices[i], prev = vertices[(i + vertices.count - 1) % vertices.count]
            let next = vertices[(i + 1) % vertices.count]
            let incoming = hypot(prev.x - v.x, prev.y - v.y)
            let outgoing = hypot(next.x - v.x, next.y - v.y)
            let radius: CGFloat = corners.contains(v) ? min(CGFloat(appearance.cornerRadius), min(incoming, outgoing) / 2) : 0
            let before = CGPoint(x: v.x + (prev.x - v.x) * radius / max(1, incoming),
                                 y: v.y + (prev.y - v.y) * radius / max(1, incoming))
            let after = CGPoint(x: v.x + (next.x - v.x) * radius / max(1, outgoing),
                                y: v.y + (next.y - v.y) * radius / max(1, outgoing))
            if i == 0 { p.move(to: before) } else { p.addLine(to: before) }
            p.addQuadCurve(to: after, control: v)
        }
        p.closeSubpath()
        return p
    }
    public static func hit(_ point: CGPoint, on a: Annotation, tolerance: CGFloat) -> Bool {
        let p = path(a)
        return p.contains(point) || p.copy(strokingWithWidth: tolerance * 2,
            lineCap: .round, lineJoin: .round, miterLimit: 10).contains(point)
    }
}
