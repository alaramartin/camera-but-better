import SwiftUI
import UIKit

struct ZoomControlView: View {
    @EnvironmentObject private var cameraManager: CameraManager

    @State private var scrubbing = false
    @State private var scrubBaselineZoom: CGFloat = 1.0
    @State private var scrubStartTranslation: CGFloat = 0
    @State private var gestureBegan = false
    @State private var holdTimer: Timer?
    @State private var pressProgress: CGFloat = 0
    @State private var demoExpanded = false
    @State private var demoCancelled = false

    @AppStorage("zoom.hintPlaysRemaining") private var hintPlaysRemaining = Constants.Zoom.hintPlayCount

    private let haptics = UISelectionFeedbackGenerator()

    private var expanded: Bool {
        scrubbing || cameraManager.isZoomGliding || demoExpanded
    }

    private var pressScale: CGFloat {
        1 + (Constants.Zoom.pressRevealScale - 1) * pressProgress
    }

    private var visibleBookmarks: [CGFloat] {
        Constants.Zoom.bookmarks.filter { $0 >= cameraManager.minZoom && $0 <= cameraManager.maxZoom }
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
            ZStack {
                if expanded {
                    ruler
                        .frame(width: rulerWidth, height: Constants.Zoom.collapsedRowHeight)
                        .clipped()
                        .mask(edgeFade)
                        .opacity(Constants.Zoom.expandedOpacity)
                        .transition(.opacity)
                } else {
                    bookmarkRow
                        .transition(.opacity)
                }
            }
        }
        .scaleEffect(pressScale)
        .frame(width: Constants.Zoom.expandedWidth)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .gesture(zoomGesture)
        .onChange(of: cameraManager.currentZoom) { oldValue, newValue in
            if Int(newValue) != Int(oldValue) {
                haptics.selectionChanged()
            }
        }
        .onAppear(perform: playIntroHintIfNeeded)
    }

    // A wordless first-run demo: auto-expand the ruler once, then collapse, so users
    // see the full scale exists and is worth reaching for. Cancelled the moment the
    // user touches the control (they have found it themselves).
    private func playIntroHintIfNeeded() {
        guard hintPlaysRemaining > 0, !expanded, !gestureBegan else { return }
        hintPlaysRemaining -= 1
        demoCancelled = false
        let grow = 0.35
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.Zoom.hintExpandDelay) {
            guard !demoCancelled else { return }
            withAnimation(.easeOut(duration: grow)) { pressProgress = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + grow) {
                guard !demoCancelled else { return }
                withAnimation(.easeInOut(duration: 0.3)) { demoExpanded = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + Constants.Zoom.hintHoldDuration) {
                    guard !demoCancelled else { return }
                    withAnimation(.easeInOut(duration: 0.3)) { demoExpanded = false }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        guard !demoCancelled else { return }
                        withAnimation(.easeOut(duration: grow)) { pressProgress = 0 }
                    }
                }
            }
        }
    }

    // The collapsed number line shares the ruler's center anchor: the current zoom is pinned
    // under the value label and never moves. Every other tick sits at a position interpolated
    // between an even bookmark spacing (compact and easy to tap at rest) and the ruler's true
    // linear spacing (as the press completes). So the line appears to stretch outward from the
    // current value into the full ruler — rightward at 1x, both ways at 5x — instead of sliding.
    private var bookmarkRow: some View {
        let bookmarks = visibleBookmarks
        let current = cameraManager.currentZoom
        let rowHeight = Constants.Zoom.collapsedRowHeight
        let midY = rowHeight / 2

        let dimOpacity = lerp(Constants.Zoom.collapsedOpacity, Constants.Zoom.expandedOpacity, Double(pressProgress))
        let minorHeight = lerp(Constants.Zoom.collapsedMinorTickHeight, Constants.Zoom.pressRevealMinorTickHeight, pressProgress)
        let majorHeight = lerp(Constants.Zoom.collapsedMajorTickHeight, Constants.Zoom.pressRevealMajorTickHeight, pressProgress)
        // Labels use the resting tick height (not the growing one) so a label never rises above
        // the frame top and gets clipped as the ticks grow into the press.
        let labelY = midY - Constants.Zoom.collapsedMajorTickHeight / 2 - Constants.Zoom.bookmarkFontSize / 2 - 2

        let center = Constants.Zoom.expandedWidth / 2
        let minorZooms = minorTickZooms(bookmarks)
        let tickXs = (bookmarks + minorZooms).map { bookmarkX($0, current: current) }
        let contentLo = tickXs.min() ?? center
        let contentHi = tickXs.max() ?? center
        // Keep the current-zoom marker (always at center) fully inside the solid region so it is
        // never dimmed by the end fades.
        let solidLo = min(contentLo, center - Constants.Zoom.markerRadius - 1)
        let solidHi = max(contentHi, center + Constants.Zoom.markerRadius + 1)
        // A fixed-length trailing fade signals more zoom that way whenever the range continues past
        // the outermost content: to the right until the current zoom reaches max, and to the left
        // only when the range dips below the first bookmark (an ultra-wide under 1x). It is a fixed
        // length rather than the exact remaining range so the cue stays visible even when the
        // current zoom sits near the limit and little space is left; a true end stops flat.
        let leftTail: CGFloat = (bookmarks.first ?? current) > cameraManager.minZoom + 0.001 ? Constants.Zoom.collapsedFadeTail : 0
        let rightTail: CGFloat = cameraManager.maxZoom > current + 0.001 ? Constants.Zoom.collapsedFadeTail : 0
        let lineLo = solidLo - leftTail
        let lineHi = solidHi + rightTail

        // Keep tickmarks running through the trailing extension so it reads as a number line fading
        // off, not a bare line. They continue the minor-tick spacing outward from the last content
        // tick and fade with the baseline under the range mask.
        let tailTickXs = trailingTickXs(contentLo: contentLo, contentHi: contentHi, lineLo: lineLo, lineHi: lineHi, leftTail: leftTail, rightTail: rightTail)

        return ZStack(alignment: .topLeading) {
            Capsule()
                .fill(Constants.Zoom.lineColor)
                .frame(width: max(0, lineHi - lineLo), height: Constants.Zoom.baselineHeight)
                .opacity(dimOpacity)
                .position(x: (lineLo + lineHi) / 2, y: midY)

            ForEach(minorZooms, id: \.self) { zoom in
                Rectangle()
                    .fill(Constants.Zoom.tickColor)
                    .frame(width: Constants.Zoom.tickWidth, height: minorHeight)
                    .opacity(dimOpacity)
                    .position(x: bookmarkX(zoom, current: current), y: midY)
            }

            ForEach(tailTickXs, id: \.self) { x in
                Rectangle()
                    .fill(Constants.Zoom.tickColor)
                    .frame(width: Constants.Zoom.tickWidth, height: minorHeight)
                    .opacity(dimOpacity)
                    .position(x: x, y: midY)
            }

            ForEach(bookmarks, id: \.self) { value in
                let cx = bookmarkX(value, current: current)
                let isActive = Int(current.rounded()) == Int(value)
                Rectangle()
                    .fill(Constants.Zoom.tickColor)
                    .frame(width: Constants.Zoom.tickWidth, height: majorHeight)
                    .opacity(isActive ? Constants.Zoom.bookmarkActiveOpacity : dimOpacity)
                    .position(x: cx, y: midY)
                Text(String(format: "%gx", value))
                    .font(.system(size: Constants.Zoom.bookmarkFontSize, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(.white)
                    .opacity((isActive ? Constants.Zoom.bookmarkActiveOpacity : Constants.Zoom.bookmarkInactiveOpacity) * Double(1 - pressProgress))
                    .shadow(radius: 2)
                    .fixedSize()
                    .position(x: cx, y: labelY)
            }

            Circle()
                .fill(Constants.Zoom.lineColor)
                .frame(width: Constants.Zoom.markerRadius * 2, height: Constants.Zoom.markerRadius * 2)
                .shadow(radius: 2)
                .position(x: bookmarkX(current, current: current), y: midY)
        }
        .frame(width: Constants.Zoom.expandedWidth, height: rowHeight, alignment: .topLeading)
        .mask(rangeFade(solidLo: solidLo, solidHi: solidHi, lineLo: lineLo, lineHi: lineHi, leftTail: leftTail, rightTail: rightTail))
    }

    // Fades a trailing extension to clear on a side that has one; a side with no tail stays fully
    // opaque out to the frame edge so an outermost label (like "1x" at min zoom) is never clipped.
    private func rangeFade(solidLo: CGFloat, solidHi: CGFloat, lineLo: CGFloat, lineHi: CGFloat, leftTail: CGFloat, rightTail: CGFloat) -> some View {
        let width = Constants.Zoom.expandedWidth
        func loc(_ x: CGFloat) -> CGFloat { max(0, min(1, x / width)) }
        var stops: [Gradient.Stop] = []
        if leftTail > 0 {
            stops.append(.init(color: .clear, location: 0))
            stops.append(.init(color: .clear, location: loc(lineLo)))
            stops.append(.init(color: .black, location: loc(solidLo)))
        } else {
            stops.append(.init(color: .black, location: 0))
        }
        if rightTail > 0 {
            stops.append(.init(color: .black, location: loc(solidHi)))
            stops.append(.init(color: .clear, location: loc(lineHi)))
            stops.append(.init(color: .clear, location: 1))
        } else {
            stops.append(.init(color: .black, location: 1))
        }
        return LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

    // Screen x for a zoom on the collapsed line, anchored so the current zoom sits at center.
    // At rest (pressProgress 0) bookmarks fall on an even index spacing; at full press they
    // reach the ruler's linear spacing, so the two representations line up when they swap.
    private func bookmarkX(_ zoom: CGFloat, current: CGFloat) -> CGFloat {
        let even = (indexCoordinate(zoom) - indexCoordinate(current)) * Constants.Zoom.bookmarkEvenSpacing
        let linear = (zoom - current) * Constants.Zoom.pointsPerZoom
        return Constants.Zoom.expandedWidth / 2 + lerp(even, linear, pressProgress)
    }

    // Position of a zoom on the evenly-spaced bookmark axis, in index units: bookmark i is at
    // i, values between bookmarks interpolate within their gap, and values past the ends
    // extrapolate along the nearest gap's slope so the current value is always placeable.
    private func indexCoordinate(_ zoom: CGFloat) -> CGFloat {
        let b = visibleBookmarks
        let n = b.count
        guard n > 1 else { return 0 }
        if zoom <= b[1] {
            return (zoom - b[0]) / (b[1] - b[0])
        }
        for i in 2..<n where zoom <= b[i] {
            return CGFloat(i - 1) + (zoom - b[i - 1]) / (b[i] - b[i - 1])
        }
        let last = b[n - 1]
        let maxZoom = cameraManager.maxZoom
        if maxZoom > last {
            return CGFloat(n - 1) + (zoom - last) / (maxZoom - last)
        }
        return CGFloat(n - 1)
    }

    private func minorTickZooms(_ bookmarks: [CGFloat]) -> [CGFloat] {
        guard bookmarks.count > 1 else { return [] }
        let per = Constants.Zoom.collapsedMinorPerGap
        var zooms: [CGFloat] = []
        for i in 1..<bookmarks.count {
            let lo = bookmarks[i - 1]
            let hi = bookmarks[i]
            for k in 1...per {
                zooms.append(lo + (hi - lo) * CGFloat(k) / CGFloat(per + 1))
            }
        }
        let last = bookmarks[bookmarks.count - 1]
        let maxZoom = cameraManager.maxZoom
        if maxZoom > last {
            for k in 1...per {
                zooms.append(last + (maxZoom - last) * CGFloat(k) / CGFloat(per + 1))
            }
        }
        return zooms
    }

    private func trailingTickXs(contentLo: CGFloat, contentHi: CGFloat, lineLo: CGFloat, lineHi: CGFloat, leftTail: CGFloat, rightTail: CGFloat) -> [CGFloat] {
        let spacing = Constants.Zoom.bookmarkEvenSpacing / CGFloat(Constants.Zoom.collapsedMinorPerGap + 1)
        var xs: [CGFloat] = []
        if rightTail > 0 {
            var x = contentHi + spacing
            while x <= lineHi {
                xs.append(x)
                x += spacing
            }
        }
        if leftTail > 0 {
            var x = contentLo - spacing
            while x >= lineLo {
                xs.append(x)
                x -= spacing
            }
        }
        return xs
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

    // A single deterministic gesture drives both interactions so there is no
    // ambiguity between a tap and a hold: a hold timer (expandHoldDuration) turns
    // a stationary press into the expanded scrubbing ruler, while a short press
    // that never expands and never moves is treated as a tap and jumps to the
    // bookmark under the touch. Movement past tapMoveSlop before the timer fires
    // cancels the hold so a stray swipe neither expands nor jumps.
    private var zoomGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if !gestureBegan {
                    gestureBegan = true
                    demoCancelled = true
                    demoExpanded = false
                    haptics.prepare()
                    startHoldTimer()
                }
                if scrubbing {
                    if scrubStartTranslation == .zero, value.translation.width != 0 {
                        scrubStartTranslation = value.translation.width
                    }
                    let delta = (value.translation.width - scrubStartTranslation) / Constants.Zoom.pointsPerZoom
                    cameraManager.setZoom(displayZoom: scrubBaselineZoom - delta)
                } else if holdTimer != nil {
                    if abs(value.translation.width) > Constants.Zoom.tapMoveSlop {
                        beginScrubbing(startTranslation: value.translation.width, duration: Constants.Zoom.dragExpandDuration)
                    } else if abs(value.translation.height) > Constants.Zoom.tapMoveSlop {
                        cancelHoldTimer()
                        resetPressProgress()
                    }
                }
            }
            .onEnded { value in
                cancelHoldTimer()
                if scrubbing {
                    cameraManager.startZoomGlide(initialVelocity: -value.velocity.width / Constants.Zoom.pointsPerZoom)
                } else if abs(value.translation.width) <= Constants.Zoom.tapMoveSlop
                    && abs(value.translation.height) <= Constants.Zoom.tapMoveSlop,
                    let target = bookmark(atLocalX: value.startLocation.x) {
                    cameraManager.animateZoom(to: target)
                }
                scrubbing = false
                gestureBegan = false
                scrubStartTranslation = 0
                resetPressProgress()
            }
    }

    // The ruler grows under the finger in proportion to how long it is held: pressProgress
    // eases 0 to 1 across the same window as the hold timer, so a tap barely moves it while
    // a sustained hold visibly blossoms the collapsed row right as it commits to expanded.
    private func startHoldTimer() {
        holdTimer?.invalidate()
        withAnimation(.linear(duration: Constants.Zoom.expandHoldDuration)) {
            pressProgress = 1
        }
        holdTimer = Timer.scheduledTimer(withTimeInterval: Constants.Zoom.expandHoldDuration, repeats: false) { _ in
            beginScrubbing(startTranslation: 0, duration: 0.2)
        }
    }

    // Commit to the expanded scrubbing ruler, either because the hold timer fired (startTranslation
    // 0, lazily anchored on first movement) or because a drag started immediately (startTranslation
    // set to the in-flight drag so the zoom does not jump, and a short duration so it snaps open).
    private func beginScrubbing(startTranslation: CGFloat, duration: Double) {
        cancelHoldTimer()
        scrubBaselineZoom = cameraManager.currentZoom
        scrubStartTranslation = startTranslation
        withAnimation(.easeOut(duration: duration)) {
            pressProgress = 1
            scrubbing = true
        }
        haptics.selectionChanged()
    }

    private func cancelHoldTimer() {
        holdTimer?.invalidate()
        holdTimer = nil
    }

    private func resetPressProgress() {
        withAnimation(.easeOut(duration: 0.2)) { pressProgress = 0 }
    }

    // Match against the resting (even-spaced) positions, not the live ones: the finger landed
    // where the bookmark was drawn at rest, but the ticks drift outward as the press grows, so a
    // far bookmark like 5x would fall out of tolerance and never register as a tap otherwise.
    private func bookmark(atLocalX x: CGFloat) -> CGFloat? {
        let current = cameraManager.currentZoom
        let center = Constants.Zoom.expandedWidth / 2
        let spacing = Constants.Zoom.bookmarkEvenSpacing
        let tolerance = spacing / 2
        var best: (distance: CGFloat, value: CGFloat)?
        for value in visibleBookmarks {
            let restX = center + (indexCoordinate(value) - indexCoordinate(current)) * spacing
            let distance = abs(x - restX)
            if distance <= tolerance, best == nil || distance < best!.distance {
                best = (distance, value)
            }
        }
        return best?.value
    }
}
