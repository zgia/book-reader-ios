import SwiftUI

struct FavoritesView: View {
    let bookId: Int
    var onSelect: ((Favorite) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var favorites: [FavoriteRow] = []

    var body: some View {
        NavigationStack {
            Group {
                if favorites.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "bookmark")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary)
                        Text(String(localized: "favorite.empty"))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(favorites) { row in
                            Button {
                                onSelect?(row.favorite)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(row.chapterTitle)
                                        .font(.headline)
                                    if let ex = row.favorite.excerpt,
                                        !ex.isEmpty
                                    {
                                        Text(ex)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                    if let idx = row.favorite.pageindex {
                                        Text(
                                            String(
                                                format: String(
                                                    localized: "favorite.page_x"
                                                ),
                                                idx + 1
                                            )
                                        )
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .swipeActions(
                                edge: .trailing,
                                allowsFullSwipe: true
                            ) {
                                Button(role: .destructive) {
                                    deleteFavorite(id: row.favorite.id)
                                } label: {
                                    Label(
                                        String(localized: "btn.delete"),
                                        systemImage: "trash"
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "favorite.title"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "multiply")
                    }
                }
            }
            .presentationDragIndicator(.visible)
            .navigationBarTitleDisplayMode(.inline)
            .presentationBackgroundInteraction(.enabled)
            .interactiveDismissDisabled(false)
            .onAppear { loadFavorites() }
        }
    }

    private func loadFavorites() {
        favorites = DatabaseManager.shared.fetchFavorites(bookId: bookId)
    }

    private func deleteFavorite(id: Int) {
        DatabaseManager.shared.deleteFavorite(id: id)
        loadFavorites()
    }
}
