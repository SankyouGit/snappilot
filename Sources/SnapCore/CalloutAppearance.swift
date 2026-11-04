import CoreGraphics
import Foundation

public enum CalloutShape: String, CaseIterable, Codable, Sendable {
    case blockArrow, arrow, bubble, roundedLabel, rectangle
    public var title: String {
        switch self {
        case .blockArrow: return "Block Arrow (Text)"
        case .arrow: return "Box + Arrow"
        case .bubble: return "Speech Bubble"
        case .roundedLabel: return "Rectangle"
        case .rectangle: return "Rectangle (Legacy)"
        }
    }
    /// Keep the old square variant decodable, but don't offer a duplicate Rectangle.
    public static var availableCases: [CalloutShape] { [.blockArrow, .arrow, .bubble, .roundedLabel] }
    public var hasPointer: Bool { self == .blockArrow || self == .arrow || self == .bubble }
}

public enum CalloutAlignment: String, CaseIterable, Codable, Sendable {
    case left, center, right
}

/// Callout-only properties, shared by objects and the existing saved-style store.
/// Optional on Annotation/AnnotationStyle so pre-existing projects and styles decode.
public struct CalloutAppearance: Equatable, Codable, Sendable {
    public var shape: CalloutShape = .arrow
    public var textColorHex: String = "#FFFFFF"
    public var borderColorHex: String = "#172B4D"
    public var borderWidth: Double = 0
    public var fontFamily: String = "System"
    public var fontSize: Double = 20
    public var bold: Bool = true
    public var alignment: CalloutAlignment = .left
    public var padding: Double = 12
    public var cornerRadius: Double = 12
    public var shadow: Bool = false
    public var pointerScale: Double = 1
    /// Optional for projects/styles saved before direct arrow controls existed.
    public var blockArrowShaftScale: Double?
    public var blockArrowBend: Double?
    public var blockArrowAutoTextSize: Bool?

    public init() {}

    public func normalized() -> CalloutAppearance {
        var out = self
        out.fontSize = min(96, max(10, fontSize))
        out.borderWidth = min(12, max(0, borderWidth))
        out.padding = min(40, max(4, padding))
        out.cornerRadius = min(40, max(0, cornerRadius))
        out.pointerScale = min(2, max(0.5, pointerScale))
        if let scale = blockArrowShaftScale { out.blockArrowShaftScale = min(2, max(0.35, scale)) }
        if let bend = blockArrowBend { out.blockArrowBend = min(1, max(-1, bend)) }
        return out
    }
}

/// UserDefaults accepts Data, not arbitrary Codable structs. Keep this boundary tested.
public enum CalloutAppearancePreferences {
    private static let key = "pref.calloutAppearance"

    public static func load(in store: UserDefaults = .standard) -> CalloutAppearance {
        guard let data = store.data(forKey: key),
              let appearance = try? JSONDecoder().decode(CalloutAppearance.self, from: data)
        else { return CalloutAppearance() }
        return appearance.normalized()
    }

    public static func save(_ appearance: CalloutAppearance, in store: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(appearance.normalized()) else { return }
        store.set(data, forKey: key)
    }
}
