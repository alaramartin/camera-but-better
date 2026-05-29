import AVFoundation
import SwiftUI

@MainActor
final class ControlsViewModel: ObservableObject {
    private enum Defaults {
        static let iso: Double = 200
        static let shutterIndex: Double = 5
        static let focusPosition: Double = 0.5
        static let whiteBalanceTemperature: Double = 5500
        static let exposureBias: Double = 0
    }

    @Published var iso: Double = Defaults.iso
    @Published var shutterIndex: Double = Defaults.shutterIndex
    @Published var focusPosition: Double = Defaults.focusPosition
    @Published var whiteBalanceTemperature: Double = Defaults.whiteBalanceTemperature
    @Published var whiteBalanceIsAuto: Bool = true
    @Published var exposureBias: Double = Defaults.exposureBias

    let shutterSpeedStops: [CMTime] = [
        CMTimeMake(value: 1, timescale: 4000),
        CMTimeMake(value: 1, timescale: 2000),
        CMTimeMake(value: 1, timescale: 1000),
        CMTimeMake(value: 1, timescale: 500),
        CMTimeMake(value: 1, timescale: 250),
        CMTimeMake(value: 1, timescale: 125),
        CMTimeMake(value: 1, timescale: 60),
        CMTimeMake(value: 1, timescale: 30),
        CMTimeMake(value: 1, timescale: 15),
        CMTimeMake(value: 1, timescale: 8),
        CMTimeMake(value: 1, timescale: 4),
    ]

    var isoLabel: String { "\(Int(iso.rounded()))" }
    var shutterSpeedLabel: String {
        let stop = shutterSpeedStops[Int(shutterIndex.rounded())]
        return "1/\(stop.timescale)"
    }
    var focusLabel: String { String(format: "%.2f", focusPosition) }
    var exposureBiasLabel: String {
        let sign = exposureBias > 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", exposureBias)) EV"
    }
    var whiteBalanceLabel: String {
        whiteBalanceIsAuto ? "Auto" : "\(Int(whiteBalanceTemperature.rounded()))K"
    }

    var shutterIndexRange: ClosedRange<Double> { 0...Double(shutterSpeedStops.count - 1) }

    private let cameraManager: CameraManager

    init(cameraManager: CameraManager) {
        self.cameraManager = cameraManager
    }

    // MARK: - Apply

    func applyISO() { cameraManager.setISO(Float(iso)) }
    func applyShutterSpeed() { cameraManager.setShutterSpeed(shutterSpeedStops[Int(shutterIndex.rounded())]) }
    func applyFocus() { cameraManager.setFocus(Float(focusPosition)) }
    func applyExposureBias() { cameraManager.setExposureBias(Float(exposureBias)) }
    func applyWhiteBalance() {
        guard !whiteBalanceIsAuto else { return }
        cameraManager.setWhiteBalance(Float(whiteBalanceTemperature))
    }

    func setWhiteBalanceAuto() {
        whiteBalanceIsAuto = true
        cameraManager.resetWhiteBalanceToAuto()
    }

    func setWhiteBalanceManual() {
        whiteBalanceIsAuto = false
        cameraManager.setWhiteBalance(Float(whiteBalanceTemperature))
    }

    // MARK: - Reset (restores continuous-auto on the device, snaps sliders to defaults visually)

    func resetISO() {
        iso = Defaults.iso
        shutterIndex = Defaults.shutterIndex
        cameraManager.resetExposureToAuto()
    }

    func resetShutterSpeed() {
        shutterIndex = Defaults.shutterIndex
        iso = Defaults.iso
        cameraManager.resetExposureToAuto()
    }

    func resetExposureBias() {
        exposureBias = Defaults.exposureBias
        cameraManager.resetExposureBias()
    }

    func resetFocus() {
        focusPosition = Defaults.focusPosition
        cameraManager.resetFocusToAuto()
    }

    func resetWhiteBalance() {
        whiteBalanceTemperature = Defaults.whiteBalanceTemperature
        whiteBalanceIsAuto = true
        cameraManager.resetWhiteBalanceToAuto()
    }

    func resetAll() {
        iso = Defaults.iso
        shutterIndex = Defaults.shutterIndex
        focusPosition = Defaults.focusPosition
        whiteBalanceTemperature = Defaults.whiteBalanceTemperature
        whiteBalanceIsAuto = true
        exposureBias = Defaults.exposureBias
        cameraManager.resetExposureToAuto()
        cameraManager.resetFocusToAuto()
        cameraManager.resetWhiteBalanceToAuto()
        cameraManager.resetExposureBias()
    }
}
