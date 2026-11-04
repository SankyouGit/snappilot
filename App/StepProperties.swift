import SwiftUI
import SnapCore

struct StepProperties: View {
    @ObservedObject var model: EditorModel
    @State private var label = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Shape", selection: $model.stepAppearance.shape) {
                ForEach(StepShape.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Text("Marker size")
            Slider(value: $model.stepAppearance.size, in: 24...100)
            Text("Font size")
            Slider(value: $model.stepAppearance.fontSize, in: 10...48)
            Picker("Font", selection: $model.stepAppearance.fontFamily) {
                ForEach(["System", "Helvetica", "Arial", "Georgia", "Menlo"], id: \.self) { Text($0).tag($0) }
            }
            Toggle("Bold", isOn: Binding(get: { model.stepAppearance.bold ?? true }, set: { model.stepAppearance.bold = $0 }))
            Text("Label padding")
            Slider(value: $model.stepAppearance.padding, in: 2...20)
            ColorPicker("Label color", selection: Binding(
                get: { Color(nsColor: nsColor(fromHex: model.stepAppearance.textColorHex ?? (model.stepAppearance.shape == .ring ? model.colorHex : "#FFFFFF"))) },
                set: { model.stepAppearance.textColorHex = hexString(fromNSColor: NSColor($0)) }), supportsOpacity: false)
            Text("Border width")
            Slider(value: $model.stepAppearance.borderWidth, in: 0...8)
            ColorPicker("Border", selection: Binding(
                get: { Color(nsColor: nsColor(fromHex: model.stepAppearance.borderColorHex)) },
                set: { model.stepAppearance.borderColorHex = hexString(fromNSColor: NSColor($0)) }), supportsOpacity: false)
            Toggle("Shadow", isOn: $model.stepAppearance.shadow)
            if model.selectedID != nil {
                HStack {
                    TextField("Label override (empty = sequence)", text: $label).onSubmit { model.setStepLabel(label) }
                    Button("Apply") { model.setStepLabel(label) }
                }
            }
        }.font(.caption)
        .onAppear { label = model.selectedID.flatMap { id in model.doc.items.first { $0.id == id }?.text } ?? "" }
    }
}
