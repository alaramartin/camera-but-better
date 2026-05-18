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
                onChange: viewModel.applyISO,
                onReset: viewModel.resetISO
            )
            ControlSliderView(
                label: "Shutter",
                valueLabel: viewModel.shutterSpeedLabel,
                value: $viewModel.shutterIndex,
                range: viewModel.shutterIndexRange,
                step: 1,
                onChange: viewModel.applyShutterSpeed,
                onReset: viewModel.resetShutterSpeed
            )
            ControlSliderView(
                label: "Focus",
                valueLabel: viewModel.focusLabel,
                value: $viewModel.focusPosition,
                range: 0...1,
                onChange: viewModel.applyFocus,
                onReset: viewModel.resetFocus
            )
            ControlSliderView(
                label: "WB",
                valueLabel: viewModel.whiteBalanceLabel,
                value: $viewModel.whiteBalanceTemperature,
                range: Double(Constants.Camera.colorTemperatureMin)...Double(Constants.Camera.colorTemperatureMax),
                onChange: viewModel.applyWhiteBalance,
                onReset: viewModel.resetWhiteBalance
            )
        }
        .padding(.vertical, 14)
    }
}
