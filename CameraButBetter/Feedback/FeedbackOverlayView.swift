import SwiftUI

struct FeedbackOverlayView: View {
    @ObservedObject var viewModel: FeedbackViewModel
    @ObservedObject var scheduler: FeedbackScheduler

    private static let defaultWidth: CGFloat = 220
    private static let defaultHeight: CGFloat = 140
    private static let minWidth: CGFloat = 160
    private static let minHeight: CGFloat = 90
    private static let maxWidth: CGFloat = 360
    private static let maxHeight: CGFloat = 420

    @State private var width: CGFloat = defaultWidth
    @State private var height: CGFloat = defaultHeight
    @State private var dragStart: CGSize?

    @State private var viewportHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0

    private var hasOverflow: Bool { contentHeight > viewportHeight + 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            scrollArea
        }
        .padding(12)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(alignment: .bottomTrailing) { resizeHandle }
    }

    @ViewBuilder
    private var scrollArea: some View {
        if #available(iOS 18.0, *) {
            modernScrollArea
        } else {
            legacyScrollArea
        }
    }

    private var scrollList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 8)
        }
    }

    @available(iOS 18.0, *)
    private var modernScrollArea: some View {
        scrollList
            .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
                ScrollMetrics(
                    offset: geometry.contentOffset.y,
                    contentHeight: geometry.contentSize.height,
                    viewportHeight: geometry.containerSize.height
                )
            } action: { _, metrics in
                scrollOffset = max(0, metrics.offset)
                contentHeight = metrics.contentHeight
                viewportHeight = metrics.viewportHeight
            }
            .overlay(alignment: .topTrailing) { scrollThumb }
    }

    private var legacyScrollArea: some View {
        GeometryReader { outer in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 8)
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: ContentHeightKey.self, value: proxy.size.height)
                            .preference(
                                key: ScrollOffsetKey.self,
                                value: -proxy.frame(in: .named("feedbackScroll")).minY
                            )
                    }
                )
            }
            .coordinateSpace(name: "feedbackScroll")
            .onPreferenceChange(ScrollOffsetKey.self) { scrollOffset = max(0, $0) }
            .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
            .onAppear { viewportHeight = outer.size.height }
            .onChange(of: outer.size.height) { _, newValue in viewportHeight = newValue }
            .overlay(alignment: .topTrailing) { scrollThumb }
        }
    }

    @ViewBuilder
    private var content: some View {
        if scheduler.isAnalyzing && viewModel.current == nil {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini).tint(.white)
                Text("Analyzing scene…")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
            }
        } else if let result = viewModel.current, !result.suggestions.isEmpty {
            ForEach(result.suggestions) { suggestion in
                suggestionRow(suggestion)
            }
        } else if let message = viewModel.lastError {
            Text(message)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(scheduler.isAnalyzing ? Color.green : Color.white.opacity(0.4))
                .frame(width: 6, height: 6)
            Text("AI COACH")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.75))
            Spacer(minLength: 8)
            Button {
                scheduler.clear()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss feedback")
        }
    }

    private func suggestionRow(_ suggestion: FeedbackSuggestion) -> some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(suggestion.category.color)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.category.rawValue)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.0)
                    .foregroundStyle(suggestion.category.color)
                Text(suggestion.text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var scrollThumb: some View {
        if hasOverflow {
            let safeViewport = max(viewportHeight, 1)
            let safeContent = max(contentHeight, safeViewport)
            let trackHeight = max(safeViewport - 32, 1)
            let ratio = min(1, safeViewport / safeContent)
            let thumbHeight = max(20, trackHeight * ratio)
            let maxOffset = max(0, safeContent - safeViewport)
            let progress = maxOffset > 0 ? min(1, scrollOffset / maxOffset) : 0
            let thumbY = (trackHeight - thumbHeight) * progress

            ZStack(alignment: .top) {
                Capsule()
                    .fill(.white.opacity(0.15))
                    .frame(width: 3, height: trackHeight)
                Capsule()
                    .fill(.white.opacity(0.75))
                    .frame(width: 3, height: thumbHeight)
                    .offset(y: thumbY)
            }
            .frame(height: trackHeight, alignment: .top)
            .padding(.trailing, 2)
            .padding(.top, 4)
            .padding(.bottom, 28)
            .allowsHitTesting(false)
        }
    }

    private var resizeHandle: some View {
        Image(systemName: "arrow.down.right")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white.opacity(0.55))
            .padding(6)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragStart == nil {
                            dragStart = CGSize(width: width, height: height)
                        }
                        guard let start = dragStart else { return }
                        let newWidth = (start.width + value.translation.width)
                            .clamped(to: Self.minWidth...Self.maxWidth)
                        let newHeight = (start.height + value.translation.height)
                            .clamped(to: Self.minHeight...Self.maxHeight)
                        width = newWidth
                        height = newHeight
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .accessibilityLabel("Resize feedback panel")
    }
}

private struct ScrollMetrics: Equatable {
    var offset: CGFloat
    var contentHeight: CGFloat
    var viewportHeight: CGFloat
}

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        max(range.lowerBound, min(range.upperBound, self))
    }
}
