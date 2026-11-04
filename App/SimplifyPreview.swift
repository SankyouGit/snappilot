import SwiftUI

struct SimplifyPreview: View {
    let original: CGImage
    let simplified: CGImage
    let onCancel: () -> Void
    let onApply: (Double) -> Void
    @State private var opacity: Double = 1
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Simplify Image").font(.title2.bold())
            ZStack {
                Image(decorative: original, scale: 1).resizable().scaledToFit()
                Image(decorative: simplified, scale: 1).resizable().scaledToFit().opacity(opacity)
            }.frame(width: 680, height: 420)
            HStack { Text("Strength"); Slider(value: $opacity, in: 0.1...1) }
            Text("Adds a movable image layer; the source image stays intact. Use Simplify Region for separately editable blocks. Use Redact for sensitive information.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Apply as Layer") { onApply(opacity) }.keyboardShortcut(.defaultAction)
            }
        }.padding(24)
    }
}
