import SwiftUI

struct PhotoDetailView: View {
    let photos: [UIImage]
    let initialIndex: Int
    @State private var currentIndex: Int

    init(photos: [UIImage], initialIndex: Int) {
        self.photos = photos
        self.initialIndex = initialIndex
        _currentIndex = State(initialValue: initialIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $currentIndex) {
                ForEach(photos.indices, id: \.self) { index in
                    Image(uiImage: photos[index])
                        .resizable()
                        .scaledToFit()
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
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
