import SwiftUI

struct ControlSliderView: View {
    let label: String
    let valueLabel: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0
    let onChange: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.white)
                .frame(width: 52, alignment: .leading)
            Group {
                if step > 0 {
                    Slider(value: $value, in: range, step: step)
                } else {
                    Slider(value: $value, in: range)
                }
            }
            .tint(.white)
            .onChange(of: value) { _, _ in onChange() }
            Text(valueLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, 12)
    }
}
