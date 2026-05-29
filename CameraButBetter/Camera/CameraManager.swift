import AVFoundation
import Combine

final class CameraManager: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published private(set) var error: String?

    @Published private(set) var currentZoom: CGFloat = 1.0
    @Published private(set) var minZoom: CGFloat = 1.0
    @Published private(set) var maxZoom: CGFloat = 1.0
    @Published private(set) var isZoomGliding = false

    private var displayMultiplier: CGFloat = 1.0
    private var wideStartFactor: CGFloat = 1.0
    private var zoomGlideTimer: Timer?

    private var device: AVCaptureDevice?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private let photoOutput = AVCapturePhotoOutput()
    let videoOutput = AVCaptureVideoDataOutput()
    let frameDelegate = FrameOutputDelegate()
    private let sessionQueue = DispatchQueue(label: "com.alaramartin.CameraButBetter.session", qos: .userInitiated)
    private let videoOutputQueue = DispatchQueue(label: "com.alaramartin.CameraButBetter.video", qos: .userInitiated)

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

        guard let device = bestAvailableCamera() else {
            DispatchQueue.main.async { self.error = "No rear camera available." }
            session.commitConfiguration()
            return
        }
        self.device = device
        rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) { session.addInput(input) }

            try device.lockForConfiguration()
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            if device.activeFormat.supportedColorSpaces.contains(.P3_D65) {
                device.activeColorSpace = .P3_D65
            }
            configureZoom(for: device)
            device.videoZoomFactor = wideStartFactor
            device.unlockForConfiguration()
            if session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
                if photoOutput.isAppleProRAWSupported {
                    photoOutput.isAppleProRAWEnabled = true
                }
                photoOutput.maxPhotoQualityPrioritization = .quality
            }
            if session.canAddOutput(videoOutput) {
                videoOutput.alwaysDiscardsLateVideoFrames = true
                videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                videoOutput.setSampleBufferDelegate(frameDelegate, queue: videoOutputQueue)
                session.addOutput(videoOutput)
            }
        } catch {
            DispatchQueue.main.async { self.error = error.localizedDescription }
            session.commitConfiguration()
            return
        }

        session.commitConfiguration()
        session.startRunning()
    }

    // MARK: - Capture

    func capturePhoto(format: PhotoFormat, delegate: AVCapturePhotoCaptureDelegate) {
        sessionQueue.async {
            if let connection = self.photoOutput.connection(with: .video),
               let angle = self.rotationCoordinator?.videoRotationAngleForHorizonLevelCapture,
               connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
            let settings = self.makeSettings(for: format)
            self.photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    private func makeSettings(for format: PhotoFormat) -> AVCapturePhotoSettings {
        if format == .raw,
           let rawFormat = photoOutput.availableRawPhotoPixelFormatTypes.first(where: {
               AVCapturePhotoOutput.isAppleProRAWPixelFormat($0)
           }) {
            let settings = AVCapturePhotoSettings(rawPixelFormatType: rawFormat, processedFormat: nil)
            settings.photoQualityPrioritization = .quality
            return settings
        }
        let settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = .quality
        return settings
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

    func setExposureBias(_ bias: Float) {
        guard let device else { return }
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                let clamped = max(device.minExposureTargetBias, min(device.maxExposureTargetBias, bias))
                device.setExposureTargetBias(clamped, completionHandler: nil)
                device.unlockForConfiguration()
            } catch {
                DispatchQueue.main.async { self.error = error.localizedDescription }
            }
        }
    }

    func resetExposureBias() {
        guard let device else { return }
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                device.setExposureTargetBias(0, completionHandler: nil)
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

    // MARK: - Zoom

    func setZoom(displayZoom: CGFloat) {
        cancelZoomGlide()
        applyZoom(displayZoom)
    }

    func cancelZoomGlide() {
        zoomGlideTimer?.invalidate()
        zoomGlideTimer = nil
        isZoomGliding = false
    }

    func startZoomGlide(initialVelocity: CGFloat) {
        cancelZoomGlide()
        guard abs(initialVelocity) > Constants.Zoom.momentumMinVelocity else { return }
        isZoomGliding = true
        var velocity = initialVelocity
        var zoom = currentZoom
        let dt = Constants.Zoom.momentumFrameInterval
        zoomGlideTimer = Timer.scheduledTimer(withTimeInterval: dt, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            velocity *= exp(-Constants.Zoom.momentumDecay * CGFloat(dt))
            zoom += velocity * CGFloat(dt)
            let clamped = zoom.clamped(to: self.minZoom...self.maxZoom)
            self.applyZoom(clamped)
            if clamped != zoom || abs(velocity) < Constants.Zoom.momentumMinVelocity {
                self.cancelZoomGlide()
            }
        }
    }

    private func applyZoom(_ displayZoom: CGFloat) {
        guard let device else { return }
        let clampedDisplay = max(minZoom, min(maxZoom, displayZoom))
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                let factor = (clampedDisplay / self.displayMultiplier)
                    .clamped(to: device.minAvailableVideoZoomFactor...device.maxAvailableVideoZoomFactor)
                device.videoZoomFactor = factor
                device.unlockForConfiguration()
                DispatchQueue.main.async { self.currentZoom = clampedDisplay }
            } catch {
                DispatchQueue.main.async { self.error = error.localizedDescription }
            }
        }
    }

    // MARK: - Auto Reset

    func resetExposureToAuto() {
        guard let device else { return }
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                device.unlockForConfiguration()
            } catch {
                DispatchQueue.main.async { self.error = error.localizedDescription }
            }
        }
    }

    func resetFocusToAuto() {
        guard let device else { return }
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                device.unlockForConfiguration()
            } catch {
                DispatchQueue.main.async { self.error = error.localizedDescription }
            }
        }
    }

    func resetWhiteBalanceToAuto() {
        guard let device else { return }
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    device.whiteBalanceMode = .continuousAutoWhiteBalance
                }
                device.unlockForConfiguration()
            } catch {
                DispatchQueue.main.async { self.error = error.localizedDescription }
            }
        }
    }

    // MARK: - Helpers

    private func bestAvailableCamera() -> AVCaptureDevice? {
        let preferred: [AVCaptureDevice.DeviceType] = [.builtInDualCamera, .builtInTripleCamera, .builtInWideAngleCamera]
        for type in preferred {
            if let device = AVCaptureDevice.default(type, for: .video, position: .back) {
                return device
            }
        }
        return AVCaptureDevice.default(for: .video)
    }

    private func configureZoom(for device: AVCaptureDevice) {
        let switchOverFactors = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }
        let constituents = device.constituentDevices

        var wideStart: CGFloat = 1.0
        if let wideIndex = constituents.firstIndex(where: { $0.deviceType == .builtInWideAngleCamera }) {
            if wideIndex > 0, wideIndex - 1 < switchOverFactors.count {
                wideStart = switchOverFactors[wideIndex - 1]
            }
        }
        wideStartFactor = wideStart
        displayMultiplier = 1.0 / wideStart

        let deviceMaxDisplay = device.maxAvailableVideoZoomFactor * displayMultiplier
        let resolvedMax = min(deviceMaxDisplay, Constants.Zoom.maxDisplay)

        DispatchQueue.main.async {
            self.minZoom = 1.0
            self.maxZoom = resolvedMax
            self.currentZoom = 1.0
        }
    }

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
