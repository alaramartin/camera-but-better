import AVFoundation
import SwiftUI

@MainActor
final class ControlsViewModel: ObservableObject {
    @Published var iso: Double = 200
    @Published var shutterIndex: Double = 5
    @Published var focusPosition: Double = 0.5
    @Published var whiteBalanceTemperature: Double = 5500

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
    var whiteBalanceLabel: String { "\(Int(whiteBalanceTemperature.rounded()))K" }

    var shutterIndexRange: ClosedRange<Double> { 0...Double(shutterSpeedStops.count - 1) }

    private let cameraManager: CameraManager

    init(cameraManager: CameraManager) {
        self.cameraManager = cameraManager
    }

    func applyISO() {
        cameraManager.setISO(Float(iso))
    }

    func applyShutterSpeed() {
        cameraManager.setShutterSpeed(shutterSpeedStops[Int(shutterIndex.rounded())])
    }

    func applyFocus() {
        cameraManager.setFocus(Float(focusPosition))
    }

    func applyWhiteBalance() {
        cameraManager.setWhiteBalance(Float(whiteBalanceTemperature))
    }
}
