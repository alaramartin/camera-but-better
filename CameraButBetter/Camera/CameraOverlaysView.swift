import SwiftUI

struct GridOverlayView: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                let columnStep = geo.size.width / 3
                let rowStep = geo.size.height / 3
                for index in 1...2 {
                    let x = columnStep * CGFloat(index)
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geo.size.height))
                    let y = rowStep * CGFloat(index)
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geo.size.width, y: y))
                }
            }
            .stroke(Constants.Overlay.gridLineColor, lineWidth: Constants.Overlay.lineWidth)
        }
        .allowsHitTesting(false)
    }
}

struct CenterCrossView: View {
    var body: some View {
        let length = Constants.Overlay.centerCrossLength
        let mid = length / 2
        Path { path in
            path.move(to: CGPoint(x: 0, y: mid))
            path.addLine(to: CGPoint(x: length, y: mid))
            path.move(to: CGPoint(x: mid, y: 0))
            path.addLine(to: CGPoint(x: mid, y: length))
        }
        .stroke(Constants.Overlay.unalignedColor, lineWidth: Constants.Overlay.lineWidth)
        .frame(width: length, height: length)
        .allowsHitTesting(false)
    }
}

struct LevelOverlayView: View {
    let tiltDegrees: Double

    private var isAligned: Bool {
        let threshold = Constants.Overlay.levelAlignedThresholdDegrees
        let normalized = abs(tiltDegrees.truncatingRemainder(dividingBy: 90))
        return min(normalized, 90 - normalized) <= threshold
    }

    var body: some View {
        Rectangle()
            .fill(isAligned ? Constants.Overlay.alignedColor : Constants.Overlay.unalignedColor)
            .frame(width: Constants.Overlay.levelLineLength, height: Constants.Overlay.lineWidth)
            .rotationEffect(.degrees(-tiltDegrees))
            .animation(.easeOut(duration: 0.1), value: tiltDegrees)
            .allowsHitTesting(false)
    }
}
