import SwiftUI

@MainActor
final class FeedbackViewModel: ObservableObject {
    @Published private(set) var current: FeedbackResult?
    @Published private(set) var history: [FeedbackResult] = []
    @Published var errorState: FeedbackErrorState?

    private let maxHistory = 20

    func record(_ result: FeedbackResult) {
        current = result
        history.append(result)
        if history.count > maxHistory {
            history.removeFirst(history.count - maxHistory)
        }
        errorState = nil
    }

    func record(errorState: FeedbackErrorState) {
        self.errorState = errorState
    }

    func clear() {
        current = nil
        errorState = nil
    }

    func dismissError() {
        errorState = nil
    }
}
