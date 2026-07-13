import AVFoundation
import Combine

final class CameraManager: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published private(set) var error: String?

    @Published private(set) var currentZoom: CGFloat = 1.0
    @Published private(set) var minZoom: CGFloat = 1.0
    @Published private(set) var maxZoom: CGFloat = 1.0
    @Published private(set) var isZoomGliding = false

    private struct PhysicalLens {
        let device: AVCaptureDevice
        let baseDisplayZoom: CGFloat
    }

    private var displayMultiplier: CGFloat = 1.0
    private var wideStartFactor: CGFloat = 1.0
    private var zoomGlideTimer: Timer?

    private var fusedDevice: AVCaptureDevice?
    private var physicalLenses: [PhysicalLens] = []
    private var activeDevice: AVCaptureDevice?
    private var currentInput: AVCaptureDeviceInput?
    private var activeBaseDisplayZoom: CGFloat = 1.0
    private var currentDisplayZoom: CGFloat = 1.0

    private var manualISO: Float?
    private var manualShutterDuration: CMTime?
    private var manualFocusPosition: Float?
    private var manualWhiteBalanceTemperature: Float?

    private var isManualActive: Bool {
        manualISO != nil || manualShutterDuration != nil || manualFocusPosition != nil || manualWhiteBalanceTemperature != nil
    }

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
        fusedDevice = device
        configureLenses(for: device)
        activeDevice = device
        activeBaseDisplayZoom = displayMultiplier
        rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
                currentInput = input
            }

            try device.lockForConfiguration()
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            if device.activeFormat.supportedColorSpaces.contains(.P3_D65) {
                device.activeColorSpace = .P3_D65
            }
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
    //
    // The fused multi-camera device used for seamless zoom cannot do custom exposure,
    // locked focus, or locked white balance. Engaging any manual control swaps the
    // session input to the physical lens covering the current zoom, where those modes
    // are supported; clearing all manual controls swaps back to the fused device.

    func setISO(_ iso: Float) {
        sessionQueue.async {
            self.manualISO = iso
            self.enterManualForCurrentZoom()
        }
    }

    func setShutterSpeed(_ duration: CMTime) {
        sessionQueue.async {
            self.manualShutterDuration = duration
            self.enterManualForCurrentZoom()
        }
    }

    func setFocus(_ lensPosition: Float) {
        sessionQueue.async {
            self.manualFocusPosition = lensPosition
            self.enterManualForCurrentZoom()
        }
    }

    func setWhiteBalance(_ temperature: Float) {
        sessionQueue.async {
            self.manualWhiteBalanceTemperature = temperature
            self.enterManualForCurrentZoom()
        }
    }

    func setExposureBias(_ bias: Float) {
        sessionQueue.async {
            guard let device = self.activeDevice else { return }
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
        sessionQueue.async {
            guard let device = self.activeDevice else { return }
            do {
                try device.lockForConfiguration()
                device.setExposureTargetBias(0, completionHandler: nil)
                device.unlockForConfiguration()
            } catch {
                DispatchQueue.main.async { self.error = error.localizedDescription }
            }
        }
    }

    // MARK: - Auto Reset

    func resetExposureToAuto() {
        sessionQueue.async {
            self.manualISO = nil
            self.manualShutterDuration = nil
            self.reevaluateManualState()
        }
    }

    func resetFocusToAuto() {
        sessionQueue.async {
            self.manualFocusPosition = nil
            self.reevaluateManualState()
        }
    }

    func resetWhiteBalanceToAuto() {
        sessionQueue.async {
            self.manualWhiteBalanceTemperature = nil
            self.reevaluateManualState()
        }
    }

    private func enterManualForCurrentZoom() {
        guard let lens = physicalLens(for: currentDisplayZoom) else { return }
        if activeDevice !== lens.device {
            switchInput(to: lens.device, baseDisplayZoom: lens.baseDisplayZoom)
            applyZoomFactor(for: currentDisplayZoom)
        }
        applyControlModes(on: activeDevice)
    }

    private func reevaluateManualState() {
        if isManualActive {
            applyControlModes(on: activeDevice)
        } else if let fusedDevice, activeDevice !== fusedDevice {
            switchInput(to: fusedDevice, baseDisplayZoom: displayMultiplier)
            applyZoomFactor(for: currentDisplayZoom)
            applyControlModes(on: activeDevice)
        } else {
            applyControlModes(on: activeDevice)
        }
    }

    private func applyControlModes(on device: AVCaptureDevice?) {
        guard let device else { return }
        do {
            try device.lockForConfiguration()

            if device.isExposureModeSupported(.custom), manualISO != nil || manualShutterDuration != nil {
                let duration = manualShutterDuration.map { clampDuration($0, for: device) } ?? AVCaptureDevice.currentExposureDuration
                let iso = manualISO.map { max(device.activeFormat.minISO, min(device.activeFormat.maxISO, $0)) } ?? AVCaptureDevice.currentISO
                device.setExposureModeCustom(duration: duration, iso: iso, completionHandler: nil)
            } else if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }

            if let focus = manualFocusPosition, device.isFocusModeSupported(.locked) {
                device.setFocusModeLocked(lensPosition: max(0, min(1, focus)), completionHandler: nil)
            } else if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }

            if let temperature = manualWhiteBalanceTemperature, device.isWhiteBalanceModeSupported(.locked) {
                let temperatureAndTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: temperature, tint: 0)
                let gains = clampGains(device.deviceWhiteBalanceGains(for: temperatureAndTint), for: device)
                device.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
            } else if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }

            device.unlockForConfiguration()
        } catch {
            DispatchQueue.main.async { self.error = error.localizedDescription }
        }
    }

    private func switchInput(to device: AVCaptureDevice, baseDisplayZoom: CGFloat) {
        guard device !== activeDevice else {
            activeBaseDisplayZoom = baseDisplayZoom
            return
        }
        session.beginConfiguration()
        let previousInput = currentInput
        if let previousInput { session.removeInput(previousInput) }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                if let previousInput, session.canAddInput(previousInput) { session.addInput(previousInput) }
                session.commitConfiguration()
                DispatchQueue.main.async { self.error = "Couldn't switch to the requested lens." }
                return
            }
            session.addInput(input)
            currentInput = input
            activeDevice = device
            activeBaseDisplayZoom = baseDisplayZoom

            try device.lockForConfiguration()
            if device.activeFormat.supportedColorSpaces.contains(.P3_D65) {
                device.activeColorSpace = .P3_D65
            }
            device.unlockForConfiguration()

            rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
            session.commitConfiguration()
        } catch {
            if let previousInput, session.canAddInput(previousInput) {
                session.addInput(previousInput)
                currentInput = previousInput
            }
            session.commitConfiguration()
            DispatchQueue.main.async { self.error = error.localizedDescription }
        }
    }

    private func physicalLens(for displayZoom: CGFloat) -> PhysicalLens? {
        guard !physicalLenses.isEmpty else { return nil }
        var chosen = physicalLenses[0]
        for lens in physicalLenses where lens.baseDisplayZoom <= displayZoom + 0.001 {
            chosen = lens
        }
        return chosen
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
        let clampedDisplay = max(minZoom, min(maxZoom, displayZoom))
        sessionQueue.async {
            self.currentDisplayZoom = clampedDisplay
            if self.isManualActive, let lens = self.physicalLens(for: clampedDisplay), lens.device !== self.activeDevice {
                self.switchInput(to: lens.device, baseDisplayZoom: lens.baseDisplayZoom)
                self.applyControlModes(on: self.activeDevice)
            }
            self.applyZoomFactor(for: clampedDisplay)
            DispatchQueue.main.async { self.currentZoom = clampedDisplay }
        }
    }

    private func applyZoomFactor(for displayZoom: CGFloat) {
        guard let device = activeDevice else { return }
        do {
            try device.lockForConfiguration()
            let factor = (displayZoom / activeBaseDisplayZoom)
                .clamped(to: device.minAvailableVideoZoomFactor...device.maxAvailableVideoZoomFactor)
            device.videoZoomFactor = factor
            device.unlockForConfiguration()
        } catch {
            DispatchQueue.main.async { self.error = error.localizedDescription }
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

    private func configureLenses(for device: AVCaptureDevice) {
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

        if constituents.isEmpty {
            physicalLenses = [PhysicalLens(device: device, baseDisplayZoom: displayMultiplier)]
        } else {
            physicalLenses = constituents.enumerated().map { index, constituent in
                let startFactor = index == 0 ? 1.0 : (index - 1 < switchOverFactors.count ? switchOverFactors[index - 1] : 1.0)
                return PhysicalLens(device: constituent, baseDisplayZoom: startFactor * displayMultiplier)
            }
            .sorted { $0.baseDisplayZoom < $1.baseDisplayZoom }
        }

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
