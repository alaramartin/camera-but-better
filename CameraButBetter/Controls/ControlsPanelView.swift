import SwiftUI

struct ControlsPanelView: View {
    @ObservedObject var viewModel: ControlsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ControlSliderView(
                label: "ISO",
                valueLabel: viewModel.isoLabel,
                value: $viewModel.iso,
                range: Constants.Camera.isoMin...Constants.Camera.isoMax,
                onChange: viewModel.applyISO
            )
            ControlSliderView(
                label: "Shutter",
                valueLabel: viewModel.shutterSpeedLabel,
                value: $viewModel.shutterIndex,
                range: viewModel.shutterIndexRange,
                step: 1,
                onChange: viewModel.applyShutterSpeed
            )
            ControlSliderView(
                label: "Focus",
                valueLabel: viewModel.focusLabel,
                value: $viewModel.focusPosition,
                range: 0...1,
                onChange: viewModel.applyFocus
            )
            ControlSliderView(
                label: "WB",
                valueLabel: viewModel.whiteBalanceLabel,
                value: $viewModel.whiteBalanceTemperature,
                range: Double(Constants.Camera.colorTemperatureMin)...Double(Constants.Camera.colorTemperatureMax),
                onChange: viewModel.applyWhiteBalance
            )
        }
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
