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
                label: "Exposure",
                valueLabel: viewModel.exposureBiasLabel,
                value: $viewModel.exposureBias,
                range: Constants.Camera.exposureBiasMin...Constants.Camera.exposureBiasMax,
                onChange: viewModel.applyExposureBias,
                onReset: viewModel.resetExposureBias
            )
            ControlSliderView(
                label: "Focus",
                valueLabel: viewModel.focusLabel,
                value: $viewModel.focusPosition,
                range: 0...1,
                onChange: viewModel.applyFocus,
                onReset: viewModel.resetFocus
            )
            whiteBalanceRow

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

    private var whiteBalanceRow: some View {
        HStack(spacing: 8) {
            Text("WB")
                .font(.caption)
                .foregroundStyle(.white)
                .frame(width: 46, alignment: .leading)
            Slider(
                value: $viewModel.whiteBalanceTemperature,
                in: Double(Constants.Camera.colorTemperatureMin)...Double(Constants.Camera.colorTemperatureMax)
            )
            .tint(.white)
            .disabled(viewModel.whiteBalanceIsAuto)
            .opacity(viewModel.whiteBalanceIsAuto ? 0.35 : 1)
            .onChange(of: viewModel.whiteBalanceTemperature) { _, _ in viewModel.applyWhiteBalance() }
            HStack(spacing: 5) {
                Button {
                    if viewModel.whiteBalanceIsAuto {
                        viewModel.setWhiteBalanceManual()
                    } else {
                        viewModel.setWhiteBalanceAuto()
                    }
                } label: {
                    Text(viewModel.whiteBalanceLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white)
                }
                Button(action: viewModel.resetWhiteBalance) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(width: 72, alignment: .trailing)
        }
        .padding(.horizontal, 12)
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
