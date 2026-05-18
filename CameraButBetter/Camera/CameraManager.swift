import AVFoundation
import Combine

final class CameraManager: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published private(set) var error: String?

    private var device: AVCaptureDevice?
    private let photoOutput = AVCapturePhotoOutput()
    let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.alaramartin.CameraButBetter.session", qos: .userInitiated)

    override init() {
        super.init()
    }

    func requestPermissionAndStart() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            if granted {
                self?.sessionQueue.async { self?.configureSession() }
            } else {
                DispatchQueue.main.async {
                    self?.error = "Camera access denied. Enable it in Settings to use this app."
                }
            }
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            DispatchQueue.main.async { self.error = "No rear camera available." }
            session.commitConfiguration()
            return
        }
        self.device = device

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) { session.addInput(input) }
            if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
            if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        } catch {
            DispatchQueue.main.async { self.error = error.localizedDescription }
            session.commitConfiguration()
            return
        }

        session.commitConfiguration()
        session.startRunning()
    }

    // MARK: - Capture

    func capturePhoto(delegate: AVCapturePhotoCaptureDelegate) {
        sessionQueue.async {
            let settings = AVCapturePhotoSettings()
            self.photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    // MARK: - Manual Controls

    func setISO(_ iso: Float) {
        guard let device else { return }
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                let clamped = max(device.activeFormat.minISO, min(device.activeFormat.maxISO, iso))
                device.setExposureModeCustom(duration: device.exposureDuration, iso: clamped, completionHandler: nil)
                device.unlockForConfiguration()
            } catch {
                DispatchQueue.main.async { self.error = error.localizedDescription }
            }
        }
    }

    func setShutterSpeed(_ duration: CMTime) {
        guard let device else { return }
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                let clamped = self.clampDuration(duration, for: device)
                device.setExposureModeCustom(duration: clamped, iso: device.iso, completionHandler: nil)
                device.unlockForConfiguration()
            } catch {
                DispatchQueue.main.async { self.error = error.localizedDescription }
            }
        }
    }

    func setFocus(_ lensPosition: Float) {
        guard let device else { return }
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                device.setFocusModeLocked(lensPosition: lensPosition, completionHandler: nil)
                device.unlockForConfiguration()
            } catch {
                DispatchQueue.main.async { self.error = error.localizedDescription }
            }
        }
    }

    func setWhiteBalance(_ temperature: Float) {
        guard let device else { return }
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                let temperatureAndTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: temperature, tint: 0)
                let gains = device.deviceWhiteBalanceGains(for: temperatureAndTint)
                let clamped = self.clampGains(gains, for: device)
                device.setWhiteBalanceModeLocked(with: clamped, completionHandler: nil)
                device.unlockForConfiguration()
            } catch {
                DispatchQueue.main.async { self.error = error.localizedDescription }
            }
        }
    }

    // MARK: - Helpers

    private func clampDuration(_ duration: CMTime, for device: AVCaptureDevice) -> CMTime {
        let minSeconds = CMTimeGetSeconds(device.activeFormat.minExposureDuration)
        let maxSeconds = CMTimeGetSeconds(device.activeFormat.maxExposureDuration)
        let seconds = CMTimeGetSeconds(duration).clamped(to: minSeconds...maxSeconds)
        return CMTimeMakeWithSeconds(seconds, preferredTimescale: duration.timescale)
    }

    private func clampGains(_ gains: AVCaptureDevice.WhiteBalanceGains, for device: AVCaptureDevice) -> AVCaptureDevice.WhiteBalanceGains {
        let maxGain = device.maxWhiteBalanceGain
        return AVCaptureDevice.WhiteBalanceGains(
            redGain: gains.redGain.clamped(to: 1.0...maxGain),
            greenGain: gains.greenGain.clamped(to: 1.0...maxGain),
            blueGain: gains.blueGain.clamped(to: 1.0...maxGain)
        )
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        max(range.lowerBound, min(range.upperBound, self))
    }
}
