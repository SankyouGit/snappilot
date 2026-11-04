import CoreGraphics

/// A free-direction quadratic arrow. Offset curves share the centerline tangent,
/// so the head, shaft, controls and rotated text cannot choose different axes.
public struct BlockArrowGeometry {
    public let body: CGRect
    public let rear: CGPoint
    public let forward: CGPoint
    public let transverse: CGPoint
    public let neckLength: CGFloat
    public let tipTransverse: CGFloat
    public let halfWidth: CGFloat
    public let headHalfWidth: CGFloat
    public let bend: CGFloat
    public let crossSize: CGFloat
    public let bodyLength: CGFloat
    public let tip: CGPoint
    public let controlX: CGFloat
    public let neckY: CGFloat
    private let headTangent: CGPoint

    public init(_ annotation: Annotation) {
        body = CalloutGeometry.body(annotation)
        let style = annotation.resolvedCalloutAppearance
        tip = annotation.pointerTip ?? CGPoint(x: body.maxX + 60, y: body.midY)
        let dx = tip.x - body.midX, dy = tip.y - body.midY
        let distance = hypot(dx, dy)
        forward = distance > 0.001 ? CGPoint(x: dx / distance, y: dy / distance) : CGPoint(x: 1, y: 0)
        transverse = CGPoint(x: -forward.y, y: forward.x)
        bodyLength = max(1, body.width)
        crossSize = max(1, body.height)
        rear = CGPoint(x: body.midX - forward.x * bodyLength / 2, y: body.midY - forward.y * bodyLength / 2)
        let length = max(1, distance + bodyLength / 2)
        tipTransverse = 0
        halfWidth = crossSize * CGFloat(style.blockArrowShaftScale ?? 1) / 2
        headHalfWidth = min(halfWidth * (1 + 0.6 * CGFloat(style.pointerScale)), max(halfWidth * 1.12, length * 0.24))
        // Keep a short/thick arrow from folding its inner offset curve over itself.
        let maximumBend = min(length * 0.24, length * length / max(1, halfWidth * 20))
        bend = min(maximumBend, max(-maximumBend, CGFloat(style.blockArrowBend ?? 0.12) * crossSize))
        controlX = length / 2
        let tangentLength = max(0.001, hypot(length - controlX, bend))
        headTangent = CGPoint(x: (length - controlX) / tangentLength, y: -bend / tangentLength)
        let depth = min(max(24, halfWidth * 1.3 * CGFloat(style.pointerScale)), length * 0.26)
        neckLength = length - headTangent.x * depth
        neckY = -headTangent.y * depth
    }

    public func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: rear.x + forward.x * x + transverse.x * y,
                y: rear.y + forward.y * x + transverse.y * y)
    }
    private func vector(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: forward.x * x + transverse.x * y, y: forward.y * x + transverse.y * y)
    }
    private func sample(_ t: CGFloat) -> (center: CGPoint, derivative: CGPoint, normal: CGPoint, normalDerivative: CGPoint) {
        let u = 1 - t
        let center = CGPoint(x: 2 * u * t * controlX + t * t * neckLength, y: 2 * u * t * bend + t * t * neckY)
        let dx = 2 * (u * controlX + t * (neckLength - controlX))
        let dy = 2 * (u * bend + t * (neckY - bend))
        let ddx = 2 * (neckLength - 2 * controlX), ddy = 2 * (neckY - 2 * bend)
        let speed = max(0.001, hypot(dx, dy))
        let normal = CGPoint(x: -dy / speed, y: dx / speed)
        let projection = (dx * ddx + dy * ddy) / (speed * speed)
        let dn = CGPoint(x: -ddy / speed - normal.x * projection, y: ddx / speed - normal.y * projection)
        return (center, CGPoint(x: dx, y: dy), normal, dn)
    }
    public func center(_ t: CGFloat) -> CGPoint {
        let c = sample(t).center
        return point(c.x, c.y)
    }
    public func normal(_ t: CGFloat) -> CGPoint {
        let n = sample(t).normal
        return vector(n.x, n.y)
    }
    public var headCenter: CGPoint { point(neckLength, neckY) }
    public var headNormal: CGPoint { vector(-headTangent.y, headTangent.x) }
    public var shaftCenter: CGPoint { center(0.25) }
    public var shaftNormal: CGPoint { normal(0.25) }
    public var textAngle: CGFloat {
        let d = sample(0.5).derivative
        let tangent = vector(d.x, d.y)
        var angle = atan2(tangent.y, tangent.x)
        // Keep labels upright even when the arrow points left.
        if angle > .pi / 2 { angle -= .pi }
        if angle < -.pi / 2 { angle += .pi }
        return angle
    }
    public var labelWidth: CGFloat { max(20, min(body.width, neckLength * 0.85)) }
    public var textOffset: CGVector {
        let c = center(0.5)
        return CGVector(dx: c.x - body.midX, dy: c.y - body.midY)
    }
    public var shaftHandle: CGPoint { CGPoint(x: shaftCenter.x + shaftNormal.x * halfWidth, y: shaftCenter.y + shaftNormal.y * halfWidth) }
    public var headHandle: CGPoint { CGPoint(x: headCenter.x + headNormal.x * headHalfWidth, y: headCenter.y + headNormal.y * headHalfWidth) }
    public var bendHandle: CGPoint { point(controlX, bend - halfWidth - 18) }

    public func minimumShaftScale(textWidth: CGFloat, textHeight: CGFloat, padding: CGFloat) -> Double {
        let c = center(0.5)
        let labelNormal = normal(0.5)
        let radius = min(0.45, textWidth / max(1, neckLength) / 2)
        var deviation: CGFloat = 0
        var cosine: CGFloat = 1
        for i in 0...8 {
            let t = 0.5 - radius + 2 * radius * CGFloat(i) / 8
            let p = center(t), n = normal(t)
            deviation = max(deviation, abs((p.x - c.x) * labelNormal.x + (p.y - c.y) * labelNormal.y))
            cosine = min(cosine, abs(n.x * labelNormal.x + n.y * labelNormal.y))
        }
        return Double((textHeight + padding * 2 + deviation * 2) / (crossSize * max(0.5, cosine)))
    }

    public var path: CGPath {
        let p = CGMutablePath()
        func offset(_ t: CGFloat, _ side: CGFloat) -> (point: CGPoint, derivative: CGPoint) {
            let s = sample(t)
            return (point(s.center.x + s.normal.x * halfWidth * side, s.center.y + s.normal.y * halfWidth * side),
                    vector(s.derivative.x + s.normalDerivative.x * halfWidth * side, s.derivative.y + s.normalDerivative.y * halfWidth * side))
        }
        func edge(_ side: CGFloat, reversed: Bool) {
            let steps = 12
            for i in 0..<steps {
                let t0 = reversed ? 1 - CGFloat(i) / CGFloat(steps) : CGFloat(i) / CGFloat(steps)
                let t1 = reversed ? 1 - CGFloat(i + 1) / CGFloat(steps) : CGFloat(i + 1) / CGFloat(steps)
                let a = offset(t0, side), b = offset(t1, side), dt = (t1 - t0) / 3
                p.addCurve(to: b.point,
                    control1: CGPoint(x: a.point.x + a.derivative.x * dt, y: a.point.y + a.derivative.y * dt),
                    control2: CGPoint(x: b.point.x - b.derivative.x * dt, y: b.point.y - b.derivative.y * dt))
            }
        }
        p.move(to: offset(0, -1).point)
        edge(-1, reversed: false)
        p.addLine(to: CGPoint(x: headCenter.x - headNormal.x * headHalfWidth, y: headCenter.y - headNormal.y * headHalfWidth))
        p.addLine(to: tip)
        p.addLine(to: headHandle)
        p.addLine(to: offset(1, 1).point)
        edge(1, reversed: true)
        let d = sample(0).derivative
        let length = max(0.001, hypot(d.x, d.y))
        p.addQuadCurve(to: offset(0, -1).point, control: point(-d.x / length * min(8, halfWidth / 3), -d.y / length * min(8, halfWidth / 3)))
        p.closeSubpath()
        return p
    }
}
