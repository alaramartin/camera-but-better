import AVKit
import SwiftUI

struct PhotoDetailView: View {
    let photos: [SessionPhoto]
    let initialIndex: Int
    @State private var currentIndex: Int

    init(photos: [SessionPhoto], initialIndex: Int) {
        self.photos = photos
        self.initialIndex = initialIndex
        _currentIndex = State(initialValue: initialIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $currentIndex) {
                ForEach(photos.indices, id: \.self) { index in
                    Group {
                        if let url = photos[index].videoURL {
                            VideoPlayer(player: AVPlayer(url: url))
                                .ignoresSafeArea()
                        } else {
                            ZoomableImageView(image: photos[index].image, index: index, currentIndex: currentIndex)
                        }
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            if photos.indices.contains(currentIndex), photos[currentIndex].isRaw {
                VStack {
                    HStack {
                        RawBadge()
                            .padding(.leading, 12)
                            .padding(.top, 8)
                        Spacer()
                    }
                    Spacer()
                }
                .allowsHitTesting(false)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("\(currentIndex + 1) / \(photos.count)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(Color.black.opacity(0.5), for: .navigationBar)
        .preferredColorScheme(.dark)
    }
}

private struct ZoomableImageView: View {
    let image: UIImage
    let index: Int
    let currentIndex: Int

    private static let minScale: CGFloat = 1.0
    private static let maxScale: CGFloat = 4.0
    private static let doubleTapScale: CGFloat = 2.5

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private var isZoomed: Bool { scale > Self.minScale }

    var body: some View {
        GeometryReader { proxy in
            let magnification = MagnifyGesture()
                .onChanged { value in
                    let startScale = lastScale
                    let newScale = clampedScale(startScale * value.magnification)
                    let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    let focal = value.startLocation
                    let focalVector = CGSize(
                        width: (focal.x - center.x - lastOffset.width) / startScale,
                        height: (focal.y - center.y - lastOffset.height) / startScale
                    )
                    let proposed = CGSize(
                        width: focal.x - center.x - focalVector.width * newScale,
                        height: focal.y - center.y - focalVector.height * newScale
                    )
                    scale = newScale
                    offset = clampedOffset(proposed, in: proxy.size)
                }
                .onEnded { _ in
                    if scale <= Self.minScale {
                        resetZoom()
                    } else {
                        lastScale = scale
                        lastOffset = offset
                    }
                }

            let drag = DragGesture()
                .onChanged { value in
                    let proposed = CGSize(
                        width: lastOffset.width + value.translation.width,
                        height: lastOffset.height + value.translation.height
                    )
                    offset = clampedOffset(proposed, in: proxy.size)
                }
                .onEnded { _ in
                    lastOffset = offset
                }

            let doubleTap = SpatialTapGesture(count: 2)
                .onEnded { value in
                    withAnimation(.easeInOut(duration: 0.25)) {
                        if isZoomed {
                            resetZoom()
                        } else {
                            zoom(to: Self.doubleTapScale, at: value.location, in: proxy.size)
                        }
                    }
                }

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(magnification)
                .highPriorityGesture(isZoomed ? drag : nil)
                .gesture(doubleTap)
        }
        .onChange(of: currentIndex) { _, newIndex in
            if newIndex != index, isZoomed {
                resetZoom()
            }
        }
    }

    private func zoom(to targetScale: CGFloat, at location: CGPoint, in size: CGSize) {
        let clamped = clampedScale(targetScale)
        scale = clamped
        lastScale = clamped
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let proposed = CGSize(
            width: -(location.x - center.x) * clamped,
            height: -(location.y - center.y) * clamped
        )
        offset = clampedOffset(proposed, in: size)
        lastOffset = offset
    }

    private func resetZoom() {
        scale = Self.minScale
        lastScale = Self.minScale
        offset = .zero
        lastOffset = .zero
    }

    private func clampedScale(_ value: CGFloat) -> CGFloat {
        min(max(value, Self.minScale), Self.maxScale)
    }

    private func clampedOffset(_ proposed: CGSize, in size: CGSize) -> CGSize {
        let maxX = max((size.width * scale - size.width) / 2, 0)
        let maxY = max((size.height * scale - size.height) / 2, 0)
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }
}
