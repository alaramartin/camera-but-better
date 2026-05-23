import SwiftUI

@main
struct CameraButBetterApp: App {
    @StateObject private var cameraManager: CameraManager
    @StateObject private var controlsViewModel: ControlsViewModel
    @StateObject private var sessionGalleryViewModel = SessionGalleryViewModel()
    @StateObject private var feedbackViewModel: FeedbackViewModel
    @StateObject private var feedbackScheduler: FeedbackScheduler

    init() {
        let manager = CameraManager()
        let controls = ControlsViewModel(cameraManager: manager)
        let feedback = FeedbackViewModel()
        let scheduler = FeedbackScheduler(
            frameProvider: manager.frameDelegate,
            controls: controls,
            feedback: feedback
        )
        _cameraManager = StateObject(wrappedValue: manager)
        _controlsViewModel = StateObject(wrappedValue: controls)
        _feedbackViewModel = StateObject(wrappedValue: feedback)
        _feedbackScheduler = StateObject(wrappedValue: scheduler)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(cameraManager)
                .environmentObject(controlsViewModel)
                .environmentObject(sessionGalleryViewModel)
                .environmentObject(feedbackViewModel)
                .environmentObject(feedbackScheduler)
        }
    }
}
