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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                previewArea
                bottomBar
            }

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
        HStack(alignment: .center) {
            topBarLeading
            Spacer()
            controlsToggle
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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

    private var controlsToggle: some View {
        HStack(spacing: 10) {
            if showControls {
                Button("Reset All") {
                    controlsViewModel.resetAll()
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .transition(.opacity)
            }
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    showControls.toggle()
                }
            } label: {
                Image(systemName: showControls ? "xmark" : "slider.horizontal.3")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showControls)
    }

    // MARK: - Preview area (framed by the selected aspect ratio)

    private var previewArea: some View {
        ZStack {
            CameraPreviewView(session: cameraManager.session)
            overlayLayer

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

            if showControls {
                VStack {
                    HStack {
                        Spacer()
                        controlsPanel
                            .padding(12)
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
        HStack {
            galleryButton
            Spacer()
            captureButton
            Spacer()
            feedbackButton
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

    private var controlsPanel: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ControlsPanelView(viewModel: controlsViewModel)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .frame(width: 250)
        .transition(.opacity)
    }

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
        .disabled(feedbackScheduler.isAnalyzing)
        .accessibilityLabel("Get AI feedback on current frame")
    }

    // MARK: - Gallery button

    private var galleryButton: some View {
        Button { showGallery = true } label: {
            if let last = sessionGalleryViewModel.sessionPhotos.last {
                Image(uiImage: last)
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
        let delegate = PhotoCaptureDelegate(aspectRatio: overlaySettings.aspectRatio, isRaw: format == .raw) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let thumbnail):
                    sessionGalleryViewModel.add(thumbnail)
                case .failure(let error):
                    self.captureError = error.localizedDescription
                    self.showCaptureError = true
                }
            }
        }
        activePhotoDelegate = delegate
        cameraManager.capturePhoto(format: format, delegate: delegate)
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
