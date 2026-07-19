import SwiftUI

struct PortraitControlView: View {
    @EnvironmentObject private var cameraManager: CameraManager

    let onToggle: (Bool) -> Void

    var body: some View {
        Button {
            onToggle(!cameraManager.isPortraitActive)
        } label: {
            Image(systemName: "camera.aperture")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(cameraManager.isPortraitActive ? Constants.Portrait.activeColor : .white)
                .frame(width: Constants.Portrait.buttonSize, height: Constants.Portrait.buttonSize)
                .background(.ultraThinMaterial, in: Circle())
                .opacity(Constants.Portrait.buttonOpacity)
                .padding(Constants.Portrait.buttonInset)
                .contentShape(Circle())
        }
    }
}
