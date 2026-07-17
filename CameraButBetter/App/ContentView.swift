import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var cameraManager: CameraManager
    @EnvironmentObject private var controlsViewModel: ControlsViewModel
    @EnvironmentObject private var sessionGalleryViewModel: SessionGalleryViewModel
    @EnvironmentObject private var feedbackViewModel: FeedbackViewModel
    @EnvironmentObject private var feedbackScheduler: FeedbackScheduler
    @EnvironmentObject private var overlaySettings: OverlaySettings
    @EnvironmentObject private var motionManager: MotionManager

    @State private var showControls = false
    @State private var showGallery = false
    @State private var showSettings = false
    @State private var captureError: String?
    @State private var showCaptureError = false
    @State private var activePhotoDelegate: PhotoCaptureDelegate?
    @State private var flashOpacity = 0.0
    @State private var shutterScale = 1.0
    @State private var panelCornerRadius: CGFloat = 1000
    @State private var recordingBlink = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                previewArea
                bottomBar
            }

            controlsMorphLayer
                .padding(.horizontal, 16)
                .padding(.top, 12)

            Color.black
                .ignoresSafeArea()
                .opacity(flashOpacity)
                .allowsHitTesting(false)
        }
        .onAppear {
            cameraManager.requestPermissionAndStart()
            if overlaySettings.showLevel { motionManager.start() }
        }
        .onDisappear { motionManager.stop() }
        .onChange(of: overlaySettings.showLevel) { _, enabled in
            if enabled { motionManager.start() } else { motionManager.stop() }
        }
        .alert("Capture Failed", isPresented: $showCaptureError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(captureError ?? "An error occurred.")
        }
        .sheet(isPresented: $showGallery) {
            SessionGalleryView(viewModel: sessionGalleryViewModel)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    // MARK: - Top bar (settings + controls toggle)

    private var topBar: some View {
        HStack(alignment: .center, spacing: 10) {
            topBarLeading
            formatIndicator
            Spacer()
            if cameraManager.isRecording {
                recordingIndicator
            } else {
                Color.clear.frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var recordingIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Constants.Recording.recordColor)
                .frame(width: 8, height: 8)
                .opacity(recordingBlink ? 1 : 0.2)
            Text(formattedDuration)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Constants.Recording.recordColor.opacity(0.25), in: Capsule())
        .overlay(Capsule().strokeBorder(Constants.Recording.recordColor.opacity(0.7), lineWidth: 1))
        .onAppear {
            recordingBlink = false
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                recordingBlink = true
            }
        }
    }

    private var formattedDuration: String {
        let total = Int(cameraManager.recordingDuration)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var topBarLeading: some View {
        Button { showSettings = true } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
        }
    }

    private var formatIndicator: some View {
        Text(overlaySettings.photoFormat.label)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(.ultraThinMaterial, in: Capsule())
    }

    private var controlsMorphLayer: some View {
        VStack(alignment: .trailing, spacing: 0) {
            HStack(spacing: 10) {
                if showControls {
                    Button("Reset All", action: controlsViewModel.resetAll)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .transition(.opacity)
                }
                Button {
                    toggleControls()
                } label: {
                    Image(systemName: showControls ? "xmark" : "slider.horizontal.3")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if showControls {
                Rectangle()
                    .fill(.white.opacity(0.15))
                    .frame(height: 0.5)
                    .padding(.horizontal, 12)
                    .transition(.opacity)

                ControlsPanelView(viewModel: controlsViewModel, manualControlsDisabled: cameraManager.isPortraitActive)
                    .transition(.opacity)
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius))
        .frame(width: showControls ? 250 : nil)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showControls)
        .disabled(cameraManager.isRecording)
        .opacity(cameraManager.isRecording ? 0.4 : 1)
    }

    private func toggleControls() {
        if showControls {
            withAnimation(.timingCurve(0.95, 0.0, 1.0, 0.2, duration: 0.4)) {
                panelCornerRadius = 1000
            }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                showControls = false
            }
        } else {
            withAnimation(.timingCurve(0.0, 0.95, 0.2, 1.0, duration: 0.25)) {
                panelCornerRadius = 16
            }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                showControls = true
            }
        }
    }

    // MARK: - Preview area (framed by the selected aspect ratio)

    private var previewArea: some View {
        ZStack {
            CameraPreviewView(session: cameraManager.session)
            if overlaySettings.bloomIntensity > 0 || cameraManager.isPortraitActive {
                EffectPreviewView(
                    frameDelegate: cameraManager.frameDelegate,
                    depthDelegate: cameraManager.depthDelegate,
                    intensity: overlaySettings.bloomIntensity,
                    portraitBlurAmount: cameraManager.isPortraitActive ? Double(overlaySettings.portraitBlurAmount) : 0
                )
            }
            overlayLayer

            VStack {
                Spacer()
                ZoomControlView()
                    .padding(.bottom, 16)
            }

            if cameraManager.isPortraitSupported {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        PortraitControlView(onToggle: setPortrait)
                            .disabled(cameraManager.isRecording)
                            .opacity(cameraManager.isRecording ? 0.4 : 1)
                    }
                }
            }

            if shouldShowOverlay {
                VStack {
                    HStack {
                        FeedbackOverlayView(viewModel: feedbackViewModel, scheduler: feedbackScheduler)
                            .padding(12)
                        Spacer()
                    }
                    Spacer()
                }
            }

            if let message = cameraManager.error {
                VStack {
                    Spacer()
                    errorBanner(message)
                        .padding(.bottom, 24)
                }
            }
        }
        .aspectRatio(overlaySettings.aspectRatio.portraitRatio, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .animation(.easeInOut(duration: 0.25), value: overlaySettings.aspectRatio)
    }

    // MARK: - Bottom bar (gallery, shutter, feedback)

    private var bottomBar: some View {
        ZStack {
            HStack {
                galleryButton
                Spacer()
                feedbackButton
            }
            captureButton
            recordButton
                .offset(x: -(36 + 16 + Constants.Recording.buttonRingSize / 2))
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
    }

    // MARK: - Composition overlays (grid, center cross, level)

    private var overlayLayer: some View {
        ZStack {
            if overlaySettings.showGrid {
                GridOverlayView()
            }
            if overlaySettings.showLevel {
                LevelOverlayView(tiltDegrees: motionManager.tiltDegrees)
            }
            if overlaySettings.showCenterCross {
                CenterCrossView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var shouldShowOverlay: Bool {
        feedbackScheduler.isAnalyzing
            || feedbackViewModel.current != nil
            || feedbackViewModel.errorState != nil
    }

    // MARK: - Controls panel (floats over the preview when open)

    // MARK: - Capture button

    private var captureButton: some View {
        Button(action: capturePhoto) {
            ZStack {
                Circle()
                    .strokeBorder(.white, lineWidth: 3)
                    .frame(width: 72, height: 72)
                Circle()
                    .fill(.white)
                    .frame(width: 60, height: 60)
                    .scaleEffect(shutterScale)
            }
        }
    }

    // MARK: - Record button

    private var recordButton: some View {
        Button(action: toggleRecording) {
            ZStack {
                Circle()
                    .strokeBorder(.white, lineWidth: 3)
                    .frame(width: Constants.Recording.buttonRingSize, height: Constants.Recording.buttonRingSize)
                if cameraManager.isRecording {
                    RoundedRectangle(cornerRadius: Constants.Recording.buttonStopCornerRadius)
                        .fill(Constants.Recording.recordColor)
                        .frame(width: Constants.Recording.buttonStopSize, height: Constants.Recording.buttonStopSize)
                } else {
                    Circle()
                        .fill(Constants.Recording.recordColor)
                        .frame(width: Constants.Recording.buttonInnerSize, height: Constants.Recording.buttonInnerSize)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: cameraManager.isRecording)
        }
        .disabled(cameraManager.isPortraitActive)
        .opacity(cameraManager.isPortraitActive ? 0.4 : 1)
        .accessibilityLabel(cameraManager.isRecording ? "Stop recording" : "Start recording")
    }

    // MARK: - Feedback button

    private var feedbackButton: some View {
        Button {
            feedbackScheduler.requestFeedback()
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 52, height: 52)
                Circle()
                    .strokeBorder(.white.opacity(0.5), lineWidth: 1)
                    .frame(width: 52, height: 52)
                if feedbackScheduler.isAnalyzing {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .disabled(feedbackScheduler.isAnalyzing || cameraManager.isRecording)
        .opacity(cameraManager.isRecording ? 0.4 : 1)
        .accessibilityLabel("Get AI feedback on current frame")
    }

    // MARK: - Gallery button

    private var galleryButton: some View {
        Button { showGallery = true } label: {
            if let latest = sessionGalleryViewModel.sessionPhotos.first {
                Image(uiImage: latest.image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.white.opacity(0.5), lineWidth: 1)
                    )
            } else {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
            }
        }
    }

    // MARK: - Error banner

    @ViewBuilder
    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding()
            .background(Color.red.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 20)
    }

    // MARK: - Photo capture

    private func capturePhoto() {
        triggerCaptureFeedback()
        let format = overlaySettings.photoFormat
        let capturedAt = Date()
        let delegate = PhotoCaptureDelegate(
            aspectRatio: overlaySettings.aspectRatio,
            isRaw: format == .raw,
            bloomIntensity: Float(overlaySettings.bloomIntensity),
            portraitBlurAmount: cameraManager.isPortraitActive ? overlaySettings.portraitBlurAmount : 0
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let thumbnail):
                    sessionGalleryViewModel.add(thumbnail, isRaw: format == .raw, capturedAt: capturedAt)
                case .failure(let error):
                    self.captureError = error.localizedDescription
                    self.showCaptureError = true
                }
            }
        }
        activePhotoDelegate = delegate
        cameraManager.capturePhoto(format: format, delegate: delegate)
    }

    // Portrait cannot share the device with the manual controls, and its blur is baked into a
    // processed image, so RAW is switched off here rather than silently overridden at capture
    // time — otherwise the format indicator would claim RAW while saving JPEG.
    private func setPortrait(_ enabled: Bool) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if enabled {
            controlsViewModel.resetAll()
            overlaySettings.photoFormat = .jpeg
        }
        cameraManager.setPortraitEnabled(enabled)
    }

    private func toggleRecording() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if cameraManager.isRecording {
            cameraManager.stopRecording()
        } else {
            let startedAt = Date()
            cameraManager.startRecording(aspectRatio: overlaySettings.aspectRatio, bloomIntensity: Float(overlaySettings.bloomIntensity)) { result in
                switch result {
                case .success(let (thumbnail, url)):
                    sessionGalleryViewModel.add(videoThumbnail: thumbnail, url: url, capturedAt: startedAt)
                case .failure(let error):
                    captureError = error.localizedDescription
                    showCaptureError = true
                }
            }
        }
    }

    private func triggerCaptureFeedback() {
        withAnimation(.easeIn(duration: 0.06)) {
            flashOpacity = 1.0
            shutterScale = 0.9
        }
        withAnimation(.easeOut(duration: 0.18).delay(0.06)) {
            flashOpacity = 0.0
            shutterScale = 1.0
        }
    }
}
