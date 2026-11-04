import SwiftUI
import SnapCore

/// Callout controls edit the same value stored in AnnotationStyle / My Styles.
struct CalloutProperties: View {
    @ObservedObject var model: EditorModel

    private func color(_ key: WritableKeyPath<CalloutAppearance, String>) -> Binding<Color> {
        Binding(get: { Color(nsColor: nsColor(fromHex: model.calloutAppearance[keyPath: key])) },
                set: { value in
                    var appearance = model.calloutAppearance
                    appearance[keyPath: key] = hexString(fromNSColor: NSColor(value))
                    model.calloutAppearance = appearance
                })
    }

    private var tailCount: Int {
        model.selectedID.flatMap { id in model.doc.items.first { $0.id == id }?.additionalPointerTips?.count } ?? 0
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CALLOUT").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            Picker("Shape", selection: Binding(
                get: { model.calloutAppearance.shape == .rectangle ? .roundedLabel : model.calloutAppearance.shape },
                set: { shape in
                    var appearance = model.calloutAppearance
                    appearance.shape = shape
                    if shape == .blockArrow {
                        appearance.alignment = .center
                        appearance.fontSize = max(28, appearance.fontSize)
                        appearance.blockArrowAutoTextSize = true
                    }
                    model.calloutAppearance = appearance
                })) {
                ForEach(CalloutShape.availableCases, id: \.self) { shape in
                    Text(shape.title).tag(shape)
                }
            }
            Picker("Font", selection: $model.calloutAppearance.fontFamily) {
                ForEach(["System", "Helvetica", "Arial", "Georgia", "Menlo"], id: \.self) { family in
                    Text(family).tag(family)
                }
            }
            HStack {
                Text("Size")
                TextField("Font size", value: Binding(
                    get: { model.calloutAppearance.fontSize },
                    set: { size in
                        var appearance = model.calloutAppearance
                        appearance.fontSize = size
                        if appearance.shape == .blockArrow { appearance.blockArrowAutoTextSize = false }
                        model.calloutAppearance = appearance
                    }), format: .number)
                    .frame(width: 50)
                Toggle("Bold", isOn: $model.calloutAppearance.bold).toggleStyle(.button)
            }
            if model.calloutAppearance.shape == .blockArrow {
                Toggle("Automatic text size", isOn: Binding(
                    get: { model.calloutAppearance.blockArrowAutoTextSize ?? true },
                    set: { value in
                        var appearance = model.calloutAppearance
                        appearance.blockArrowAutoTextSize = value
                        model.calloutAppearance = appearance
                    }))
            }
            ColorPicker("Text", selection: color(\.textColorHex), supportsOpacity: false)
            Picker("Alignment", selection: $model.calloutAppearance.alignment) {
                Image(systemName: "text.alignleft").tag(CalloutAlignment.left)
                Image(systemName: "text.aligncenter").tag(CalloutAlignment.center)
                Image(systemName: "text.alignright").tag(CalloutAlignment.right)
            }.pickerStyle(.segmented)
            ColorPicker("Outline", selection: color(\.borderColorHex), supportsOpacity: false)
            slider("Outline width", value: $model.calloutAppearance.borderWidth, range: 0...12)
            if model.calloutAppearance.borderWidth > 0 {
                Picker("Outline style", selection: $model.lineStyle) {
                    ForEach(LineStyle.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
            }
            slider("Padding", value: $model.calloutAppearance.padding, range: 4...40)
            if [.arrow, .bubble, .roundedLabel].contains(model.calloutAppearance.shape) {
                slider("Corner radius", value: $model.calloutAppearance.cornerRadius, range: 0...40)
            }
            if model.calloutAppearance.shape.hasPointer {
                slider(model.calloutAppearance.shape == .blockArrow ? "Arrowhead size" : "Tail size", value: $model.calloutAppearance.pointerScale, range: 0.5...2)
            }
            if model.calloutAppearance.shape == .blockArrow {
                slider("Shaft thickness", value: Binding(
                    get: { model.calloutAppearance.blockArrowShaftScale ?? 1 },
                    set: { model.calloutAppearance.blockArrowShaftScale = $0 }), range: 0.35...2)
                slider("Bend", value: Binding(
                    get: { model.calloutAppearance.blockArrowBend ?? 0.12 },
                    set: { model.calloutAppearance.blockArrowBend = $0 }), range: -1...1)
                Text("Drag yellow handles for thickness and head size. Drag the blue handle to bend.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Rotation")
                Slider(value: Binding(
                    get: { model.calloutAppearance.rotationDegrees ?? 0 },
                    set: { value in
                        var appearance = model.calloutAppearance
                        appearance.rotationDegrees = value
                        model.calloutAppearance = appearance
                    }), in: -180...180).accessibilityLabel("Callout rotation")
            }
            if [.arrow, .bubble].contains(model.calloutAppearance.shape) {
                Toggle("Automatic tail attachment", isOn: Binding(
                    get: { model.calloutAppearance.pointerAnchorOffset == nil },
                    set: { automatic in
                        var appearance = model.calloutAppearance
                        appearance.pointerAnchorOffset = automatic ? nil : 0.5
                        model.calloutAppearance = appearance
                    }))
                if model.calloutAppearance.pointerAnchorOffset != nil {
                    Slider(value: Binding(get: { model.calloutAppearance.pointerAnchorOffset ?? 0.5 },
                        set: { model.calloutAppearance.pointerAnchorOffset = $0 }), in: 0.05...0.95)
                        .accessibilityLabel("Tail attachment along edge")
                }
            }
            if [.arrow, .bubble, .thought].contains(model.calloutAppearance.shape) {
                HStack {
                    Button("Add Tail") { model.addCalloutTail() }.disabled(tailCount >= 3)
                    Button("Remove Tail") { model.removeCalloutTail() }.disabled(tailCount == 0)
                }.disabled(model.selectedID == nil)
                Text("Drag yellow endpoints independently. Green handle rotates the object.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Toggle("Shadow", isOn: $model.calloutAppearance.shadow)
            Button("Reset Appearance") {
                var defaults = CalloutAppearance()
                defaults.shape = model.calloutAppearance.shape
                model.applyCalloutPreset(color: "#153E75", appearance: defaults)
            }.buttonStyle(.bordered)
        }
        .font(.caption)
    }

    private func slider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text(value.wrappedValue, format: .number.precision(.fractionLength(0...1)))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range).accessibilityLabel(label)
        }
    }
}
