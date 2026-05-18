import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var cameraManager: CameraManager
    @EnvironmentObject private var controlsViewModel: ControlsViewModel

    @State private var showControls = false
    @State private var captureError: String?
    @State private var showCaptureError = false
    @State private var activePhotoDelegate: PhotoCaptureDelegate?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraPreviewView(session: cameraManager.session)
                .ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    controlsContainer
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                Spacer()
            }

            VStack {
                Spacer()
                captureButton
                    .padding(.bottom, 40)
            }

            if let message = cameraManager.error {
                VStack {
                    Spacer()
                    errorBanner(message)
                        .padding(.bottom, 130)
                }
            }
        }
        .onAppear {
            cameraManager.requestPermissionAndStart()
        }
        .alert("Capture Failed", isPresented: $showCaptureError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(captureError ?? "An error occurred.")
        }
    }

    // MARK: - Controls container (morphs between button and panel)

    private var controlsContainer: some View {
        VStack(alignment: .trailing, spacing: 0) {
            HStack(spacing: 10) {
                if showControls {
                    Button("Reset All", action: controlsViewModel.resetAll)
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

                ControlsPanelView(viewModel: controlsViewModel)
                    .transition(.opacity)
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: showControls ? 16 : .infinity))
        .frame(width: showControls ? 250 : nil)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showControls)
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
        let delegate = PhotoCaptureDelegate { result in
            if case .failure(let error) = result {
                DispatchQueue.main.async {
                    self.captureError = error.localizedDescription
                    self.showCaptureError = true
                }
            }
        }
        activePhotoDelegate = delegate
        cameraManager.capturePhoto(delegate: delegate)
    }
}
