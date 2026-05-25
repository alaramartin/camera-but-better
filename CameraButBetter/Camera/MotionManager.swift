import CoreMotion
import Foundation

@MainActor
final class MotionManager: ObservableObject {
    @Published private(set) var tiltDegrees: Double = 0

    private let motionManager = CMMotionManager()
    private var isActive = false

    func start() {
        guard !isActive, motionManager.isDeviceMotionAvailable else { return }
        isActive = true
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let gravity = motion?.gravity else { return }
            let radians = atan2(gravity.x, -gravity.y)
            self.tiltDegrees = radians * 180 / .pi
        }
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        motionManager.stopDeviceMotionUpdates()
        tiltDegrees = 0
    }
}
