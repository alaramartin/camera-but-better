import SwiftUI

struct ControlsPanelView: View {
    @ObservedObject var viewModel: ControlsViewModel
    @EnvironmentObject private var overlaySettings: OverlaySettings

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

            Rectangle()
                .fill(.white.opacity(0.15))
                .frame(height: 0.5)
                .padding(.horizontal, 12)

            overlayToggle("Level", isOn: $overlaySettings.showLevel)
            overlayToggle("Grid", isOn: $overlaySettings.showGrid)
            overlayToggle("Center", isOn: $overlaySettings.showCenterCross)
        }
        .padding(.vertical, 14)
    }

    private func overlayToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.white)
                .frame(width: 46, alignment: .leading)
        }
        .padding(.horizontal, 12)
    }
}
