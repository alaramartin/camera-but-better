import SwiftUI

@MainActor
final class FeedbackViewModel: ObservableObject {
    @Published private(set) var current: FeedbackResult?
    @Published private(set) var history: [FeedbackResult] = []
    @Published var lastError: String?

    private let maxHistory = 20

    func record(_ result: FeedbackResult) {
        current = result
        history.append(result)
        if history.count > maxHistory {
            history.removeFirst(history.count - maxHistory)
        }
        lastError = nil
    }

    func record(error: Error) {
        lastError = error.localizedDescription
    }

    func clear() {
        current = nil
        lastError = nil
    }

    func dismissError() {
        lastError = nil
    }
}
