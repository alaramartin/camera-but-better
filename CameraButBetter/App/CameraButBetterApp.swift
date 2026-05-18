import SwiftUI

@main
struct CameraButBetterApp: App {
    @StateObject private var cameraManager: CameraManager
    @StateObject private var controlsViewModel: ControlsViewModel
    @StateObject private var sessionGalleryViewModel = SessionGalleryViewModel()

    init() {
        let manager = CameraManager()
        _cameraManager = StateObject(wrappedValue: manager)
        _controlsViewModel = StateObject(wrappedValue: ControlsViewModel(cameraManager: manager))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(cameraManager)
                .environmentObject(controlsViewModel)
                .environmentObject(sessionGalleryViewModel)
        }
    }
}
