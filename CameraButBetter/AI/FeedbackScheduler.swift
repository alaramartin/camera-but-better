import Foundation
import SwiftUI

@MainActor
final class FeedbackScheduler: ObservableObject {
    @Published private(set) var isAnalyzing = false

    private let frameProvider: FrameOutputDelegate
    private let controls: ControlsViewModel
    private let feedback: FeedbackViewModel
    private let overlaySettings: OverlaySettings
    private let openRouter: OpenRouterService
    private let gemini: GeminiService

    private var currentTask: Task<Void, Never>?

    init(frameProvider: FrameOutputDelegate,
         controls: ControlsViewModel,
         feedback: FeedbackViewModel,
         overlaySettings: OverlaySettings,
         openRouter: OpenRouterService = OpenRouterService(),
         gemini: GeminiService = GeminiService()) {
        self.frameProvider = frameProvider
        self.controls = controls
        self.feedback = feedback
        self.overlaySettings = overlaySettings
        self.openRouter = openRouter
        self.gemini = gemini
    }

    func requestFeedback() {
        runGemma()
    }

    func retryGemma() {
        runGemma()
    }

    private func runGemma() {
        analyze(provider: "Gemma") { base64, iso, shutter in
            try await self.openRouter.analyze(imageBase64: base64, currentISO: iso, currentShutter: shutter)
        } onError: { [weak self] error in
            self?.gemmaErrorState(for: error) ?? FeedbackErrorState(
                message: error.localizedDescription, canRetryGemma: false, canSwitchToGemini: false
            )
        }
    }

    func switchToGemini() {
        analyze(provider: "Gemini") { base64, iso, shutter in
            try await self.gemini.analyze(imageBase64: base64, currentISO: iso, currentShutter: shutter)
        } onError: { error in
            FeedbackErrorState(message: error.localizedDescription, canRetryGemma: false, canSwitchToGemini: false)
        }
    }

    private func gemmaErrorState(for error: Error) -> FeedbackErrorState? {
        guard let feedbackError = error as? FeedbackError else { return nil }
        let message = feedbackError.localizedDescription
        switch feedbackError.failureKind {
        case .transient:
            return FeedbackErrorState(message: message, canRetryGemma: true, canSwitchToGemini: true)
        case .userDailyLimit:
            return FeedbackErrorState(message: message, canRetryGemma: false, canSwitchToGemini: true)
        case .client:
            return FeedbackErrorState(message: message, canRetryGemma: false, canSwitchToGemini: false)
        }
    }

    private func analyze(provider: String,
                         run: @escaping (String, String, String) async throws -> FeedbackResult,
                         onError: @escaping (Error) -> FeedbackErrorState) {
        guard !isAnalyzing else { return }
        guard let buffer = frameProvider.takeLatestBuffer(),
              let base64 = ImageConverter.base64JPEG(from: buffer, aspectRatio: overlaySettings.aspectRatio) else {
            feedback.record(errorState: FeedbackErrorState(
                message: FeedbackError.invalidResponse.localizedDescription,
                canRetryGemma: false,
                canSwitchToGemini: false
            ))
            return
        }

        let iso = controls.isoLabel
        let shutter = controls.shutterSpeedLabel
        isAnalyzing = true
        currentTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isAnalyzing = false }
            do {
                let result = try await run(base64, iso, shutter)
                if Task.isCancelled { return }
                self.feedback.record(result)
            } catch {
                if Task.isCancelled { return }
                self.feedback.record(errorState: onError(error))
            }
        }
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        isAnalyzing = false
    }

    func clear() {
        cancel()
        feedback.clear()
    }
}
