import CoreGraphics

/// Grab points on a selected annotation: the two ends of a line/arrow, or the four corners
/// of a box-shaped annotation. Badge-like annotations (text, step, stamp, pen) have none.
public enum AnnotationHandle: Equatable, Sendable {
    case start, end, pointerTip, shaftWidth, arrowheadSize, arrowBend, rotation
    case additionalPointer(Int)
    case topLeft, topRight, bottomLeft, bottomRight

    public static func handles(for a: Annotation) -> [(AnnotationHandle, CGPoint)] {
        var handles = baseHandles(for: a)
        if a.isModernCallout {
            if a.resolvedCalloutAppearance.shape.hasPointer && a.resolvedCalloutAppearance.shape != .blockArrow {
                handles += (a.additionalPointerTips ?? []).enumerated().map { (.additionalPointer($0.offset), $0.element) }
            }
            let r = CalloutGeometry.body(a)
            handles.append((.rotation, CGPoint(x: r.midX, y: r.minY - 30)))
            handles = handles.map { ($0.0, CalloutGeometry.rotate($0.1, on: a)) }
        }
        return handles
    }
    private static func baseHandles(for a: Annotation) -> [(AnnotationHandle, CGPoint)] {
        switch a.tool {
        case .arrow, .line:
            return [(.start, a.start), (.end, a.end)]
        case .rect, .ellipse, .highlight, .blur, .spotlight, .magnify, .callout:
            let r = selectionRect(from: a.start, to: a.end)
            let tip: [(AnnotationHandle, CGPoint)] = a.resolvedCalloutAppearance.shape.hasPointer ? (a.pointerTip.map { [(.pointerTip, $0)] } ?? []) : []
            let controls: [(AnnotationHandle, CGPoint)]
            if a.tool == .callout && a.resolvedCalloutAppearance.shape == .blockArrow {
                let geometry = BlockArrowGeometry(a)
                controls = [(.shaftWidth, geometry.shaftHandle), (.arrowheadSize, geometry.headHandle), (.arrowBend, geometry.bendHandle)]
            } else { controls = [] }
            return controls + tip + [(.topLeft, CGPoint(x: r.minX, y: r.minY)), (.topRight, CGPoint(x: r.maxX, y: r.minY)),
                    (.bottomLeft, CGPoint(x: r.minX, y: r.maxY)), (.bottomRight, CGPoint(x: r.maxX, y: r.maxY))]
        case .step:
            if a.stepAppearance != nil && a.resolvedStepAppearance.shape == .pin { return [(.pointerTip, StepGeometry.tip(a))] }
            return []
        case .text, .stamp, .pen, .crop, .smartMove:
            return []
        }
    }

    /// The handle within `tolerance` of `point`, nearest first.
    public static func hit(_ point: CGPoint, on a: Annotation, tolerance: CGFloat) -> AnnotationHandle? {
        handles(for: a)
            .map { ($0.0, hypot(point.x - $0.1.x, point.y - $0.1.y)) }
            .filter { $0.1 <= tolerance }
            .min { $0.1 < $1.1 }?.0
    }

    /// `original` with this handle dragged to `point`. Corners resize against the opposite
    /// corner and can be dragged past it (the box flips, as in any drawing app).
    public func dragged(_ original: Annotation, to worldPoint: CGPoint) -> Annotation {
        var out = original
        let point = original.isModernCallout ? CalloutGeometry.rotate(worldPoint, on: original, inverse: true) : worldPoint
        switch self {
        case .rotation:
            let r = CalloutGeometry.body(original)
            var style = original.resolvedCalloutAppearance
            style.rotationDegrees = Double(atan2(worldPoint.y - r.midY, worldPoint.x - r.midX) * 180 / .pi + 90)
            out.calloutAppearance = style.normalized()
        case .additionalPointer(let index):
            if out.additionalPointerTips?.indices.contains(index) == true { out.additionalPointerTips?[index] = point }
        case .shaftWidth, .arrowheadSize, .arrowBend:
            let geometry = BlockArrowGeometry(original)
            var style = original.resolvedCalloutAppearance
            func transverseDistance(from anchor: CGPoint) -> CGFloat {
                (point.x - anchor.x) * geometry.transverse.x + (point.y - anchor.y) * geometry.transverse.y
            }
            switch self {
            case .shaftWidth:
                let center = geometry.shaftCenter, normal = geometry.shaftNormal
                let distance = (point.x - center.x) * normal.x + (point.y - center.y) * normal.y
                style.blockArrowShaftScale = Double(abs(distance) * 2 / geometry.crossSize)
            case .arrowheadSize:
                let neck = geometry.headCenter, normal = geometry.headNormal
                let distance = (point.x - neck.x) * normal.x + (point.y - neck.y) * normal.y
                style.pointerScale = Double((abs(distance) / max(1, geometry.halfWidth) - 1) / 0.6)
            case .arrowBend:
                let middle = geometry.point(geometry.controlX, 0)
                style.blockArrowBend = Double((transverseDistance(from: middle) + geometry.halfWidth + 18) / geometry.crossSize)
            default: break
            }
            out.calloutAppearance = style.normalized()
        case .pointerTip: out.pointerTip = point
        case .start: out.start = point
        case .end: out.end = point
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            let r = selectionRect(from: original.start, to: original.end)
            let anchor: CGPoint
            switch self {
            case .topLeft: anchor = CGPoint(x: r.maxX, y: r.maxY)
            case .topRight: anchor = CGPoint(x: r.minX, y: r.maxY)
            case .bottomLeft: anchor = CGPoint(x: r.maxX, y: r.minY)
            default: anchor = CGPoint(x: r.minX, y: r.minY)
            }
            out.start = anchor
            out.end = point
        }
        if original.isModernCallout {
            switch self {
            case .topLeft, .topRight, .bottomLeft, .bottomRight:
                out.pointerTip = original.pointerTip.map { CalloutGeometry.rotate(CalloutGeometry.rotate($0, on: original), on: out, inverse: true) }
                out.additionalPointerTips = original.additionalPointerTips?.map { CalloutGeometry.rotate(CalloutGeometry.rotate($0, on: original), on: out, inverse: true) }
            default: break
            }
        }
        return out
    }
}
