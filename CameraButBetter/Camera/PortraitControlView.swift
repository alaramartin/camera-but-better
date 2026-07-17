import SwiftUI
import UIKit

struct PortraitControlView: View {
    @EnvironmentObject private var cameraManager: CameraManager
    @EnvironmentObject private var overlaySettings: OverlaySettings

    let onToggle: (Bool) -> Void

    @GestureState private var isTouching = false
    @State private var wheelRevealed = false
    // Reset when a touch begins rather than when it ends, so the tap-versus-hold decision in
    // onEnded cannot race the GestureState reset that collapses the wheel.
    @State private var didReveal = false
    @State private var revealTask: Task<Void, Never>?
    @State private var dragBaseline: Double?

    private let haptics = UISelectionFeedbackGenerator()

    private var containerSize: CGFloat {
        Constants.Portrait.wheelRadius + Constants.Portrait.buttonSize + Constants.Portrait.buttonInset
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if wheelRevealed {
                wheel
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
            button
        }
        .frame(width: containerSize, height: containerSize, alignment: .bottomTrailing)
        .animation(.easeOut(duration: 0.2), value: wheelRevealed)
        .onChange(of: isTouching) { _, touching in
            if !touching {
                revealTask?.cancel()
                revealTask = nil
                wheelRevealed = false
                dragBaseline = nil
            }
        }
        .onChange(of: overlaySettings.portraitStopIndex) { oldValue, newValue in
            if Int(newValue) != Int(oldValue) {
                haptics.selectionChanged()
            }
        }
    }

    private var button: some View {
        Image(systemName: "camera.aperture")
            .font(.system(size: 20, weight: .regular))
            .foregroundStyle(cameraManager.isPortraitActive ? Constants.Portrait.activeColor : .white)
            .frame(width: Constants.Portrait.buttonSize, height: Constants.Portrait.buttonSize)
            .background(.ultraThinMaterial, in: Circle())
            .opacity(wheelRevealed ? Constants.Portrait.expandedOpacity : Constants.Portrait.collapsedOpacity)
            .padding(Constants.Portrait.buttonInset)
            .contentShape(Circle())
            .gesture(apertureGesture)
    }

    // The wheel is a quarter of a dial centred on the button, sweeping from the left round
    // to straight up. Ticks scroll under a fixed indicator, so the value at the indicator is
    // always the current stop and nothing is drawn beyond the ends of the scale.
    private var wheel: some View {
        Canvas { context, size in
            let center = CGPoint(
                x: size.width - Constants.Portrait.buttonInset - Constants.Portrait.buttonSize / 2,
                y: size.height - Constants.Portrait.buttonInset - Constants.Portrait.buttonSize / 2
            )
            let radius = Constants.Portrait.wheelRadius
            let current = overlaySettings.portraitStopIndex

            var arc = Path()
            arc.addArc(
                center: center,
                radius: radius,
                startAngle: .degrees(Constants.Portrait.arcStartDegrees),
                endAngle: .degrees(Constants.Portrait.arcEndDegrees),
                clockwise: false
            )
            context.stroke(
                arc,
                with: .color(Constants.Portrait.lineColor),
                lineWidth: Constants.Portrait.baselineWidth
            )

            let steps = Int((Constants.Portrait.stopIndexMax - Constants.Portrait.stopIndexMin))
                * Constants.Portrait.ticksPerStop
            for step in 0...steps {
                let stop = Constants.Portrait.stopIndexMin
                    + Double(step) / Double(Constants.Portrait.ticksPerStop)
                let degrees = Constants.Portrait.indicatorDegrees
                    + (stop - current) * Constants.Portrait.degreesPerStop
                guard degrees >= Constants.Portrait.arcStartDegrees,
                      degrees <= Constants.Portrait.arcEndDegrees
                else { continue }

                let isMajor = step % Constants.Portrait.ticksPerStop == 0
                let length = isMajor ? Constants.Portrait.majorTickLength : Constants.Portrait.minorTickLength
                context.stroke(
                    Self.tickPath(center: center, radius: radius, degrees: degrees, length: length),
                    with: .color(Constants.Portrait.tickColor),
                    lineWidth: Constants.Portrait.tickWidth
                )
            }

            context.stroke(
                Self.tickPath(
                    center: center,
                    radius: radius,
                    degrees: Constants.Portrait.indicatorDegrees,
                    length: Constants.Portrait.majorTickLength * 1.6
                ),
                with: .color(Constants.Portrait.activeColor),
                lineWidth: Constants.Portrait.tickWidth * 3
            )

            let labelPoint = Self.point(
                center: center,
                radius: radius - Constants.Portrait.majorTickLength - 18,
                degrees: Constants.Portrait.indicatorDegrees
            )
            context.draw(
                Text(overlaySettings.portraitApertureLabel)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white),
                at: labelPoint
            )
        }
    }

    private static func point(center: CGPoint, radius: CGFloat, degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(x: center.x + cos(radians) * radius, y: center.y + sin(radians) * radius)
    }

    private static func tickPath(center: CGPoint, radius: CGFloat, degrees: Double, length: CGFloat) -> Path {
        var path = Path()
        path.move(to: point(center: center, radius: radius - length / 2, degrees: degrees))
        path.addLine(to: point(center: center, radius: radius + length / 2, degrees: degrees))
        return path
    }

    // A single drag gesture owns both interactions: sequencing a long press ahead of a drag
    // would swallow quick taps. If the wheel never revealed, the touch was a tap.
    private var apertureGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .updating($isTouching) { _, state, _ in state = true }
            .onChanged { value in
                let baseline: Double
                if let existing = dragBaseline {
                    baseline = existing
                } else {
                    baseline = overlaySettings.portraitStopIndex
                    dragBaseline = baseline
                    didReveal = false
                    haptics.prepare()
                    beginReveal()
                }
                guard cameraManager.isPortraitActive else { return }
                // A decisive drag should not have to wait out the reveal timer.
                if abs(value.translation.height) > Constants.Portrait.revealDistance {
                    revealTask?.cancel()
                    revealTask = nil
                    reveal()
                }
                guard wheelRevealed else { return }
                let delta = Double(value.translation.height) / Double(Constants.Portrait.pointsPerStop)
                overlaySettings.portraitStopIndex = (baseline + delta)
                    .clamped(to: Constants.Portrait.stopIndexMin...Constants.Portrait.stopIndexMax)
            }
            .onEnded { _ in
                revealTask?.cancel()
                revealTask = nil
                if !didReveal {
                    onToggle(!cameraManager.isPortraitActive)
                }
                wheelRevealed = false
                dragBaseline = nil
            }
    }

    private func beginReveal() {
        guard cameraManager.isPortraitActive else { return }
        revealTask?.cancel()
        revealTask = Task {
            try? await Task.sleep(for: .seconds(Constants.Portrait.revealDelay))
            guard !Task.isCancelled else { return }
            reveal()
        }
    }

    private func reveal() {
        wheelRevealed = true
        didReveal = true
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        max(range.lowerBound, min(range.upperBound, self))
    }
}
