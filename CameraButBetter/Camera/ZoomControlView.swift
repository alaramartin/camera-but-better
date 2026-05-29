import SwiftUI
import UIKit

struct ZoomControlView: View {
    @EnvironmentObject private var cameraManager: CameraManager

    @GestureState private var isActive = false
    @State private var dragBaseline: CGFloat?

    private let haptics = UISelectionFeedbackGenerator()

    private var expanded: Bool {
        isActive || cameraManager.isZoomGliding
    }

    private var rulerWidth: CGFloat {
        expanded ? Constants.Zoom.expandedWidth : Constants.Zoom.collapsedWidth
    }

    var body: some View {
        VStack(spacing: 10) {
            Text(String(format: "%.1fx", cameraManager.currentZoom))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(radius: 2)
            ruler
                .frame(width: rulerWidth, height: Constants.Zoom.wholeTickHeight)
                .clipped()
                .mask(edgeFade)
                .opacity(expanded ? Constants.Zoom.expandedOpacity : Constants.Zoom.collapsedOpacity)
                .animation(.easeOut(duration: 0.2), value: expanded)
        }
        .frame(width: Constants.Zoom.expandedWidth)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .gesture(zoomGesture)
        .onChange(of: cameraManager.currentZoom) { oldValue, newValue in
            if Int(newValue) != Int(oldValue) {
                haptics.selectionChanged()
            }
        }
    }

    private var edgeFade: some View {
        let fade = Constants.Zoom.edgeFadeFraction
        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: fade),
                .init(color: .black, location: 1 - fade),
                .init(color: .clear, location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // A measuring-tape ruler: the current zoom sits at the center, the scale
    // scrolls beneath it. Tick at zoom z is offset (z - currentZoom) * pointsPerZoom,
    // so the value under the centered label is always currentZoom, and nothing is
    // drawn outside [minZoom, maxZoom].
    private var ruler: some View {
        let current = cameraManager.currentZoom
        let minZoom = cameraManager.minZoom
        let maxZoom = cameraManager.maxZoom
        let pointsPerZoom = Constants.Zoom.pointsPerZoom
        let halfWidth = rulerWidth / 2

        let baselineStart = max(-halfWidth, (minZoom - current) * pointsPerZoom)
        let baselineEnd = min(halfWidth, (maxZoom - current) * pointsPerZoom)

        let lowZoom = max(minZoom, current - halfWidth / pointsPerZoom)
        let highZoom = min(maxZoom, current + halfWidth / pointsPerZoom)
        let firstTick = Int((lowZoom / 0.1).rounded(.up))
        let lastTick = Int((highZoom / 0.1).rounded(.down))

        return ZStack {
            if baselineEnd > baselineStart {
                Capsule()
                    .fill(Constants.Zoom.lineColor)
                    .frame(width: baselineEnd - baselineStart, height: Constants.Zoom.baselineHeight)
                    .offset(x: (baselineStart + baselineEnd) / 2)
            }
            if lastTick >= firstTick {
                ForEach(firstTick...lastTick, id: \.self) { index in
                    let zoom = CGFloat(index) * 0.1
                    Rectangle()
                        .fill(Constants.Zoom.tickColor)
                        .frame(width: Constants.Zoom.tickWidth, height: tickHeight(forTenths: index))
                        .offset(x: (zoom - current) * pointsPerZoom)
                }
            }
        }
    }

    private func tickHeight(forTenths index: Int) -> CGFloat {
        if index % 10 == 0 { return Constants.Zoom.wholeTickHeight }
        if index % 5 == 0 { return Constants.Zoom.halfTickHeight }
        return Constants.Zoom.minorTickHeight
    }

    private var zoomGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .updating($isActive) { _, state, _ in state = true }
            .onChanged { value in
                let baseline: CGFloat
                if let existing = dragBaseline {
                    baseline = existing
                } else {
                    baseline = cameraManager.currentZoom
                    dragBaseline = baseline
                    haptics.prepare()
                }
                let delta = value.translation.width / Constants.Zoom.pointsPerZoom
                cameraManager.setZoom(displayZoom: baseline - delta)
            }
            .onEnded { value in
                dragBaseline = nil
                cameraManager.startZoomGlide(initialVelocity: -value.velocity.width / Constants.Zoom.pointsPerZoom)
            }
    }
}
