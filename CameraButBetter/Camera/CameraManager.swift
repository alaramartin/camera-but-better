import AVFoundation
import Combine
import Photos
import UIKit

final class CameraManager: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published private(set) var error: String?

    @Published private(set) var currentZoom: CGFloat = 1.0
    @Published private(set) var minZoom: CGFloat = 1.0
    @Published private(set) var maxZoom: CGFloat = 1.0
    @Published private(set) var isZoomGliding = false

    @Published private(set) var isRecording = false
    @Published private(set) var recordingDuration: TimeInterval = 0

    @Published private(set) var isPortraitSupported = false
    @Published private(set) var isPortraitActive = false

    private struct PhysicalLens {
        let device: AVCaptureDevice
        let baseDisplayZoom: CGFloat
    }

    private var displayMultiplier: CGFloat = 1.0
    private var wideStartFactor: CGFloat = 1.0
    private var zoomGlideTimer: Timer?

    private var fusedDevice: AVCaptureDevice?
    // Portrait runs on its own device: the wide+tele pair only overlaps within the tele's
    // narrow field of view, so depth there forces the framing to roughly 3x. Ultra-wide+wide
    // overlap across the whole wide frame, which is what allows portrait at 1x.
    private var portraitDevice: AVCaptureDevice?
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
    private var zoomRangeObservations: [NSKeyValueObservation] = []
    private let photoOutput = AVCapturePhotoOutput()
    let videoOutput = AVCaptureVideoDataOutput()
    let frameDelegate = FrameOutputDelegate()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let depthDataOutput = AVCaptureDepthDataOutput()
    let depthDelegate = DepthOutputDelegate()
    let subjectMaskProvider = SubjectMaskProvider()
    private var portraitLock = false
    private var audioInput: AVCaptureDeviceInput?
    private var recorder: VideoRecorder?
    private var recordingCompletion: ((Result<(UIImage, URL), Error>) -> Void)?
    private var recordingLock = false
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?
    private let sessionQueue = DispatchQueue(label: "com.alaramartin.CameraButBetter.session", qos: .userInitiated)
    private let videoOutputQueue = DispatchQueue(label: "com.alaramartin.CameraButBetter.video", qos: .userInitiated)
    private let depthOutputQueue = DispatchQueue(label: "com.alaramartin.CameraButBetter.depth", qos: .userInitiated)

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
        observeZoomRange(on: device)

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

        portraitDevice = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back)
        let supportsPortrait = portraitDevice != nil
        DispatchQueue.main.async { self.isPortraitSupported = supportsPortrait }

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
        if format == .raw, !portraitLock,
           let rawFormat = photoOutput.availableRawPhotoPixelFormatTypes.first(where: {
               AVCapturePhotoOutput.isAppleProRAWPixelFormat($0)
           }) {
            let settings = AVCapturePhotoSettings(rawPixelFormatType: rawFormat, processedFormat: nil)
            settings.photoQualityPrioritization = .quality
            return settings
        }
        let settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = .quality
        if portraitLock, photoOutput.isDepthDataDeliveryEnabled {
            settings.isDepthDataDeliveryEnabled = true
            settings.isPortraitEffectsMatteDeliveryEnabled = photoOutput.isPortraitEffectsMatteDeliveryEnabled
            // The effect is baked in and the result re-encoded, which drops auxiliary data
            // anyway, so embedding the map would only produce a payload we discard.
            settings.embedsDepthDataInPhoto = false
            settings.embedsPortraitEffectsMatteInPhoto = false
        }
        return settings
    }

    // MARK: - Video Recording

    func startRecording(aspectRatio: PreviewAspectRatio, bloomIntensity: Float, completion: @escaping (Result<(UIImage, URL), Error>) -> Void) {
        guard !isRecording, !isPortraitActive else { return }
        let orientation = Self.currentImageOrientation()
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            guard let self else { return }
            guard granted else {
                DispatchQueue.main.async {
                    self.error = "Microphone access denied. Enable it in Settings to record video with sound."
                }
                return
            }
            self.sessionQueue.async {
                self.beginRecording(orientation: orientation, aspectRatio: aspectRatio, bloomIntensity: bloomIntensity, completion: completion)
            }
        }
    }

    private func beginRecording(orientation: CGImagePropertyOrientation, aspectRatio: PreviewAspectRatio, bloomIntensity: Float, completion: @escaping (Result<(UIImage, URL), Error>) -> Void) {
        session.beginConfiguration()
        if audioInput == nil, let device = AVCaptureDevice.default(for: .audio) {
            if let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
                session.addInput(input)
                audioInput = input
            }
        }
        if session.canAddOutput(audioOutput) {
            session.addOutput(audioOutput)
        }
        session.commitConfiguration()

        let recorder = VideoRecorder()
        audioOutput.setSampleBufferDelegate(recorder, queue: recorder.recordingQueue)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CBB_\(UUID().uuidString).mov")
        recorder.start(url: url, orientation: orientation, aspectRatio: aspectRatio, bloomIntensity: bloomIntensity)
        frameDelegate.setFrameHandler({ [weak recorder] buffer in recorder?.appendVideo(buffer) }, forKey: "recorder")

        self.recorder = recorder
        self.recordingCompletion = completion
        self.recordingLock = true

        DispatchQueue.main.async {
            self.recordingStartTime = Date()
            self.recordingDuration = 0
            self.isRecording = true
            self.startRecordingTimer()
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        stopRecordingTimer()
        isRecording = false
        frameDelegate.removeFrameHandler(forKey: "recorder")
        let recorder = self.recorder
        sessionQueue.async {
            self.recordingLock = false
            self.session.beginConfiguration()
            self.audioOutput.setSampleBufferDelegate(nil, queue: nil)
            if self.session.outputs.contains(self.audioOutput) {
                self.session.removeOutput(self.audioOutput)
            }
            if let audioInput = self.audioInput {
                self.session.removeInput(audioInput)
                self.audioInput = nil
            }
            self.session.commitConfiguration()

            recorder?.finish { result in
                switch result {
                case .success(let url):
                    self.finalizeVideo(url)
                case .failure(let error):
                    DispatchQueue.main.async {
                        self.recordingCompletion?(.failure(error))
                        self.recordingCompletion = nil
                    }
                }
                self.recorder = nil
            }
        }
    }

    private func finalizeVideo(_ url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    self.recordingCompletion?(.failure(PhotoCaptureDelegate.CaptureError.photoLibraryDenied))
                    self.recordingCompletion = nil
                }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: url, options: nil)
            } completionHandler: { success, error in
                let thumbnail = self.videoThumbnail(for: url)
                DispatchQueue.main.async {
                    if success, let thumbnail {
                        self.recordingCompletion?(.success((thumbnail, url)))
                    } else {
                        self.recordingCompletion?(.failure(error ?? PhotoCaptureDelegate.CaptureError.noData))
                    }
                    self.recordingCompletion = nil
                }
            }
        }
    }

    private func videoThumbnail(for url: URL) -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1200, height: 1200)
        guard let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func startRecordingTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let start = self.recordingStartTime else { return }
            self.recordingDuration = Date().timeIntervalSince(start)
        }
    }

    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingStartTime = nil
    }

    private static func currentImageOrientation() -> CGImagePropertyOrientation {
        let interfaceOrientation = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.interfaceOrientation ?? .portrait
        switch interfaceOrientation {
        case .portrait: return .right
        case .portraitUpsideDown: return .left
        case .landscapeLeft: return .down
        case .landscapeRight: return .up
        default: return .right
        }
    }

    // MARK: - Manual Controls
    //
    // The fused multi-camera device used for seamless zoom cannot do custom exposure,
    // locked focus, or locked white balance. Engaging any manual control swaps the
    // session input to the physical lens covering the current zoom, where those modes
    // are supported; clearing all manual controls swaps back to the fused device.

    func setISO(_ iso: Float) {
        sessionQueue.async {
            guard !self.recordingLock, !self.portraitLock else { return }
            self.manualISO = iso
            self.enterManualForCurrentZoom()
        }
    }

    func setShutterSpeed(_ duration: CMTime) {
        sessionQueue.async {
            guard !self.recordingLock, !self.portraitLock else { return }
            self.manualShutterDuration = duration
            self.enterManualForCurrentZoom()
        }
    }

    func setFocus(_ lensPosition: Float) {
        sessionQueue.async {
            guard !self.recordingLock, !self.portraitLock else { return }
            self.manualFocusPosition = lensPosition
            self.enterManualForCurrentZoom()
        }
    }

    func setWhiteBalance(_ temperature: Float) {
        sessionQueue.async {
            guard !self.recordingLock, !self.portraitLock else { return }
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

    // MARK: - Portrait
    //
    // Depth delivery needs the fused device, which is the same device the manual controls
    // cannot use. Portrait therefore clears manual state, swaps back to the fused device,
    // and holds portraitLock so nothing swaps the input away while depth is streaming.

    func setPortraitEnabled(_ enabled: Bool) {
        sessionQueue.async {
            guard self.isPortraitSupported, !self.recordingLock else { return }
            guard enabled != self.portraitLock else { return }
            if enabled {
                self.enablePortrait()
            } else {
                self.disablePortrait()
            }
        }
    }

    private func enablePortrait() {
        guard let portraitDevice else {
            DispatchQueue.main.async { self.error = "Portrait mode isn't available on this camera." }
            return
        }

        manualISO = nil
        manualShutterDuration = nil
        manualFocusPosition = nil
        manualWhiteBalanceTemperature = nil

        switchInput(to: portraitDevice, baseDisplayZoom: 1.0 / Self.wideStartFactor(for: portraitDevice))
        guard activeDevice === portraitDevice else {
            DispatchQueue.main.async { self.error = "Couldn't switch to the portrait lens." }
            return
        }
        applyControlModes(on: activeDevice)

        // Only meaningful once the portrait device is the session's input.
        guard photoOutput.isDepthDataDeliverySupported, session.canAddOutput(depthDataOutput) else {
            revertToFusedDevice()
            DispatchQueue.main.async { self.error = "Portrait mode isn't available on this camera." }
            return
        }

        session.beginConfiguration()
        session.addOutput(depthDataOutput)
        // Without filtering the map is speckled with holes, which reads as noise in the mask.
        depthDataOutput.isFilteringEnabled = true
        depthDataOutput.setDelegate(depthDelegate, callbackQueue: depthOutputQueue)
        if let connection = depthDataOutput.connection(with: .depthData) {
            connection.isEnabled = true
        }
        photoOutput.isDepthDataDeliveryEnabled = true
        // Requires depth delivery already enabled. Person-only: when no person is in frame
        // the capture simply arrives without a matte and the depth-only path applies.
        photoOutput.isPortraitEffectsMatteDeliveryEnabled = photoOutput.isPortraitEffectsMatteDeliverySupported

        do {
            try portraitDevice.lockForConfiguration()
            if let depthFormat = Self.bestDepthFormat(for: portraitDevice.activeFormat) {
                portraitDevice.activeDepthDataFormat = depthFormat
            }
            portraitDevice.unlockForConfiguration()
        } catch {
            DispatchQueue.main.async { self.error = error.localizedDescription }
        }
        session.commitConfiguration()

        frameDelegate.setFrameHandler({ [subjectMaskProvider, depthDelegate] sampleBuffer in
            subjectMaskProvider.submit(
                sampleBuffer,
                disparity: depthDelegate.takeLatestFrame()?.disparity.pixelBuffer
            )
        }, forKey: "subjectMask")

        portraitLock = true
        refreshZoomBounds()
        DispatchQueue.main.async { self.isPortraitActive = true }
    }

    private func disablePortrait() {
        portraitLock = false
        session.beginConfiguration()
        depthDataOutput.setDelegate(nil, callbackQueue: nil)
        photoOutput.isPortraitEffectsMatteDeliveryEnabled = false
        photoOutput.isDepthDataDeliveryEnabled = false
        if session.outputs.contains(depthDataOutput) {
            session.removeOutput(depthDataOutput)
        }
        session.commitConfiguration()

        frameDelegate.removeFrameHandler(forKey: "subjectMask")
        subjectMaskProvider.clear()
        depthDelegate.clear()
        revertToFusedDevice()
        DispatchQueue.main.async { self.isPortraitActive = false }
    }

    private func revertToFusedDevice() {
        guard let fusedDevice else { return }
        switchInput(to: fusedDevice, baseDisplayZoom: displayMultiplier)
        applyControlModes(on: activeDevice)
        refreshZoomBounds()
    }

    // Streaming depth narrows the device's usable zoom range: stereo only works where both
    // cameras see the subject, so the device raises its own minimum. That happens
    // asynchronously after commitConfiguration, and reading the range straight afterwards
    // returns the old values — the device then silently clamps videoZoomFactor upward while
    // the UI still shows the zoom the user asked for. Observing it is the only way to stay
    // in sync with what the hardware actually did.
    private func observeZoomRange(on device: AVCaptureDevice) {
        zoomRangeObservations = [
            device.observe(\.minAvailableVideoZoomFactor) { [weak self] _, _ in
                self?.sessionQueue.async { self?.refreshZoomBounds() }
            },
            device.observe(\.maxAvailableVideoZoomFactor) { [weak self] _, _ in
                self?.sessionQueue.async { self?.refreshZoomBounds() }
            }
        ]
    }

    private func refreshZoomBounds() {
        guard let device = activeDevice else { return }
        // The floor keeps 1.0x meaning the wide lens everywhere. It also matters for portrait:
        // the dual-wide device would otherwise reach down to the ultra-wide, where there is no
        // second camera below it to derive depth from.
        let deviceMin = max(1.0, device.minAvailableVideoZoomFactor * activeBaseDisplayZoom)
        let deviceMax = min(device.maxAvailableVideoZoomFactor * activeBaseDisplayZoom, Constants.Zoom.maxDisplay)
        guard deviceMax > deviceMin else { return }

        let clamped = currentDisplayZoom.clamped(to: deviceMin...deviceMax)
        currentDisplayZoom = clamped
        applyZoomFactor(for: clamped)

        DispatchQueue.main.async {
            self.minZoom = deviceMin
            self.maxZoom = deviceMax
            self.currentZoom = clamped
        }
    }

    private static func bestDepthFormat(for format: AVCaptureDevice.Format) -> AVCaptureDevice.Format? {
        format.supportedDepthDataFormats.max { first, second in
            CMVideoFormatDescriptionGetDimensions(first.formatDescription).width
                < CMVideoFormatDescriptionGetDimensions(second.formatDescription).width
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
        guard !recordingLock, !portraitLock else { return }
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
            // The incoming device starts at its own zoom factor of 1.0, which is a wider lens
            // than the one being replaced. Setting the zoom inside this configuration block
            // means the first frame it delivers is already correctly framed; correcting it
            // after the commit lets a few frames escape at the wrong focal length.
            device.videoZoomFactor = (currentDisplayZoom / baseDisplayZoom)
                .clamped(to: device.minAvailableVideoZoomFactor...device.maxAvailableVideoZoomFactor)
            device.unlockForConfiguration()

            rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
            observeZoomRange(on: device)
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

    // Display zoom is anchored so that 1.0x is the wide lens, whichever virtual device is
    // active: this is the video zoom factor at which that device reaches its wide camera.
    private static func wideStartFactor(for device: AVCaptureDevice) -> CGFloat {
        let switchOverFactors = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }
        guard let wideIndex = device.constituentDevices.firstIndex(where: { $0.deviceType == .builtInWideAngleCamera }),
              wideIndex > 0,
              wideIndex - 1 < switchOverFactors.count
        else { return 1.0 }
        return switchOverFactors[wideIndex - 1]
    }

    private func configureLenses(for device: AVCaptureDevice) {
        let switchOverFactors = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }
        let constituents = device.constituentDevices

        let wideStart = Self.wideStartFactor(for: device)
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
