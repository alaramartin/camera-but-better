import Foundation
import SwiftUI

@MainActor
final class FeedbackScheduler: ObservableObject {
    @Published private(set) var isAnalyzing = false

    private let frameProvider: FrameOutputDelegate
    private let controls: ControlsViewModel
    private let feedback: FeedbackViewModel
    private let service: GeminiService

    private var currentTask: Task<Void, Never>?

    init(frameProvider: FrameOutputDelegate,
         controls: ControlsViewModel,
         feedback: FeedbackViewModel,
         service: GeminiService = GeminiService()) {
        self.frameProvider = frameProvider
        self.controls = controls
        self.feedback = feedback
        self.service = service
    }

    func requestFeedback() {
        guard !isAnalyzing else { return }
        guard KeychainService.shared.hasAPIKey else {
            feedback.record(error: GeminiError.missingAPIKey)
            return
        }
        guard let buffer = frameProvider.takeLatestBuffer(),
              let base64 = ImageConverter.base64JPEG(from: buffer) else {
            feedback.record(error: GeminiError.invalidResponse)
            return
        }

        let iso = controls.isoLabel
        let shutter = controls.shutterSpeedLabel
        isAnalyzing = true
        currentTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isAnalyzing = false }
            do {
                let result = try await self.service.analyze(
                    imageBase64: base64,
                    currentISO: iso,
                    currentShutter: shutter
                )
                if Task.isCancelled { return }
                self.feedback.record(result)
            } catch {
                if Task.isCancelled { return }
                self.feedback.record(error: error)
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
