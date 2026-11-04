import CoreGraphics
import Foundation

public enum StepShape: String, CaseIterable, Codable, Sendable {
    case circle, roundedSquare, pin, ring
    public var title: String {
        switch self {
        case .circle: return "Circle"
        case .roundedSquare: return "Rounded Square"
        case .pin: return "Pin"
        case .ring: return "Outline Circle"
        }
    }
}
public struct StepAppearance: Codable, Equatable, Sendable {
    public var shape: StepShape = .circle
    public var size: Double = 40
    public var fontSize: Double = 22
    public var fontFamily: String = "System"
    public var textColorHex: String?
    public var borderColorHex: String = "#FFFFFF"
    public var borderWidth: Double = 2
    public var padding: Double = 6
    public var shadow: Bool = false
    public init() {}
    public func normalized() -> StepAppearance {
        var out = self
        out.size = min(180, max(24, size))
        out.fontSize = min(96, max(10, fontSize))
        out.borderWidth = min(12, max(0, borderWidth))
        out.padding = min(30, max(2, padding))
        return out
    }
}
public enum StepAppearancePreferences {
    public static func load(in store: UserDefaults = .standard) -> StepAppearance {
        store.data(forKey: "pref.stepAppearance").flatMap { try? JSONDecoder().decode(StepAppearance.self, from: $0) }?.normalized() ?? StepAppearance()
    }
    public static func save(_ appearance: StepAppearance, in store: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(appearance.normalized()) { store.set(data, forKey: "pref.stepAppearance") }
    }
}
public enum StepGeometry {
    public static func body(_ a: Annotation) -> CGRect {
        let style = a.resolvedStepAppearance
        let labelWidth = Double(a.stepLabel.count) * style.fontSize * 0.65 + style.padding * 2
        let diameter = CGFloat(max(style.size, labelWidth))
        return CGRect(x: a.start.x - diameter / 2, y: a.start.y - diameter / 2, width: diameter, height: diameter)
    }
    public static func tip(_ a: Annotation) -> CGPoint {
        a.pointerTip ?? CGPoint(x: a.start.x, y: a.start.y + body(a).height)
    }
    public static func path(_ a: Annotation) -> CGPath {
        let r = body(a), shape = a.resolvedStepAppearance.shape
        if shape == .roundedSquare { return CGPath(roundedRect: r, cornerWidth: r.width * 0.18, cornerHeight: r.height * 0.18, transform: nil) }
        let circle = CGPath(ellipseIn: r, transform: nil)
        guard shape == .pin else { return circle }
        let p = tip(a), dx = p.x - a.start.x, dy = p.y - a.start.y, length = max(1, hypot(dx, dy))
        let nx = dx / length, ny = dy / length, half = r.width * 0.32
        let triangle = CGMutablePath()
        triangle.move(to: CGPoint(x: a.start.x - ny * half, y: a.start.y + nx * half))
        triangle.addLine(to: p)
        triangle.addLine(to: CGPoint(x: a.start.x + ny * half, y: a.start.y - nx * half))
        triangle.closeSubpath()
        return circle.union(triangle)
    }
    public static func bounds(_ a: Annotation) -> CGRect {
        let style = a.resolvedStepAppearance
        return path(a).boundingBoxOfPath.insetBy(dx: -CGFloat(style.borderWidth / 2 + (style.shadow ? 12 : 0)), dy: -CGFloat(style.borderWidth / 2 + (style.shadow ? 12 : 0)))
    }
}
