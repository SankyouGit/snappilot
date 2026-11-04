import CoreGraphics

/// Extra callout families share their path and inscribed text region with export.
public enum CalloutBodyShapes {
    public static func path(_ a: Annotation) -> CGPath {
        let r = CalloutGeometry.body(a), shape = a.resolvedCalloutAppearance.shape
        if shape == .ellipse { return CGPath(ellipseIn: r, transform: nil) }
        let path = CGMutablePath()
        if shape == .burst {
            let count = 24
            for i in 0..<count {
                let angle = CGFloat(i) * 2 * .pi / CGFloat(count) - .pi / 2
                let radius: CGFloat = i.isMultiple(of: 2) ? 1 : 0.75
                let p = CGPoint(x: r.midX + cos(angle) * r.width / 2 * radius,
                                y: r.midY + sin(angle) * r.height / 2 * radius)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
            return path
        }
        // A smooth scalloped ellipse, using cubic Hermite segments of the radial curve.
        func sample(_ t: CGFloat) -> (CGPoint, CGPoint) {
            let radius = 0.91 + 0.07 * cos(t * 10)
            let derivative = -0.7 * sin(t * 10)
            let p = CGPoint(x: r.midX + cos(t) * radius * r.width / 2,
                            y: r.midY + sin(t) * radius * r.height / 2)
            let d = CGPoint(x: (-sin(t) * radius + cos(t) * derivative) * r.width / 2,
                            y: (cos(t) * radius + sin(t) * derivative) * r.height / 2)
            return (p, d)
        }
        path.move(to: sample(0).0)
        for i in 0..<80 {
            let t0 = CGFloat(i) * 2 * .pi / 80, t1 = CGFloat(i + 1) * 2 * .pi / 80
            let (p, dp) = sample(t0), (q, dq) = sample(t1), dt = (t1 - t0) / 3
            path.addCurve(to: q, control1: CGPoint(x: p.x + dp.x * dt, y: p.y + dp.y * dt),
                          control2: CGPoint(x: q.x - dq.x * dt, y: q.y - dq.y * dt))
        }
        path.closeSubpath()
        if shape == .thought, let tip = a.pointerTip, !r.contains(tip) {
            let dx = tip.x - r.midX, dy = tip.y - r.midY
            let ratio = 1 / max(abs(dx) / max(1, r.width / 2), abs(dy) / max(1, r.height / 2))
            let anchor = CGPoint(x: r.midX + dx * ratio, y: r.midY + dy * ratio)
            for (fraction, radius) in [(CGFloat(0.25), CGFloat(8)), (0.60, 5), (1, 2.5)] {
                let p = CGPoint(x: anchor.x + (tip.x - anchor.x) * fraction, y: anchor.y + (tip.y - anchor.y) * fraction)
                let size = radius * CGFloat(a.resolvedCalloutAppearance.pointerScale)
                path.addEllipse(in: CGRect(x: p.x - size, y: p.y - size, width: size * 2, height: size * 2))
            }
        }
        return path
    }
}
