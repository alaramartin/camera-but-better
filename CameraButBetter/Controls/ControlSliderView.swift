import SwiftUI

struct ControlSliderView: View {
    let label: String
    let valueLabel: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0
    let onChange: () -> Void
    let onReset: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.white)
                .frame(width: 46, alignment: .leading)
            Group {
                if step > 0 {
                    Slider(value: $value, in: range, step: step)
                } else {
                    Slider(value: $value, in: range)
                }
            }
            .tint(.white)
            .onChange(of: value) { _, _ in onChange() }
            HStack(spacing: 5) {
                Text(valueLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white)
                Button(action: onReset) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(width: 72, alignment: .trailing)
        }
        .padding(.horizontal, 12)
    }
}
