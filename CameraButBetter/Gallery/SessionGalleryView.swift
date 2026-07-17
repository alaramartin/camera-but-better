import SwiftUI

struct SessionGalleryView: View {
    @ObservedObject var viewModel: SessionGalleryViewModel
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.sessionPhotos.isEmpty {
                    emptyState
                } else {
                    photoGrid
                }
            }
            .background(.black)
            .navigationTitle("Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.black.opacity(0.85), for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No photos this session")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var photoGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(viewModel.sessionPhotos.enumerated()), id: \.element.id) { index, photo in
                    NavigationLink {
                        PhotoDetailView(photos: viewModel.sessionPhotos, initialIndex: index)
                    } label: {
                        Color.clear
                            .aspectRatio(3.0 / 4.0, contentMode: .fit)
                            .overlay(
                                Image(uiImage: photo.image)
                                    .resizable()
                                    .scaledToFill()
                            )
                            .clipped()
                            .overlay(alignment: .topLeading) {
                                if photo.isRaw {
                                    RawBadge()
                                        .padding(6)
                                }
                            }
                            .overlay {
                                if photo.isVideo {
                                    Image(systemName: "play.circle.fill")
                                        .font(.system(size: 28))
                                        .foregroundStyle(.white.opacity(0.9))
                                        .shadow(radius: 3)
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct RawBadge: View {
    var body: some View {
        Text("RAW")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
    }
}
