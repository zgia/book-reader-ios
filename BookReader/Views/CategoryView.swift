import SwiftUI

struct CategoryView: View {
    @EnvironmentObject private var db: DatabaseManager

    @State private var categories: [Category] = []
    @State private var newTitle: String = ""
    @State private var renaming: Category? = nil
    @State private var renameText: String = ""

    var body: some View {
        List {
            Section(header: Text(String(localized: "category.management"))) {
                HStack {
                    TextField(
                        String(localized: "category.new_placeholder"),
                        text: $newTitle
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    Button(String(localized: "btn_add")) { addCategory() }
                        .disabled(
                            newTitle.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty
                        )
                }
            }

            Section {
                if categories.isEmpty {
                    Text(String(localized: "category.empty")).foregroundColor(
                        .secondary
                    )
                } else {
                    ForEach(categories) { cat in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(cat.title)
                                Text(
                                    cat.ishidden == 1
                                        ? String(localized: "category.hidden")
                                        : String(localized: "category.visible")
                                )
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            }
                            Spacer()
                            Menu {
                                Button(String(localized: "btn_rename")) {
                                    renaming = cat
                                    renameText = cat.title
                                }
                                Button(
                                    cat.ishidden == 1
                                        ? String(localized: "btn_show")
                                        : String(localized: "btn_hide")
                                ) {
                                    db.updateCategoryHidden(
                                        id: cat.id,
                                        isHidden: cat.ishidden == 0
                                    )
                                    load()
                                }
                                Button(
                                    String(localized: "btn_delete"),
                                    role: .destructive
                                ) {
                                    db.deleteCategory(id: cat.id)
                                    load()
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(String(localized: "category.title"))
        .onAppear { load() }
        .overlay(renamingOverlay())
    }

    private func load() {
        categories = db.fetchCategories(includeHidden: true)
    }

    private func addCategory() {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = db.insertCategory(title: trimmed)
        newTitle = ""
        load()
    }

    @ViewBuilder
    private func renamingOverlay() -> some View {
        if let cat = renaming {
            TextFieldDialog(
                title: String(localized: "category.rename_title"),
                placeholder: String(localized: "category.rename_placeholder"),
                text: $renameText,
                onCancel: { renaming = nil },
                onSave: {
                    let t = renameText.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    guard !t.isEmpty else {
                        renaming = nil
                        return
                    }
                    db.updateCategoryTitle(id: cat.id, title: t)
                    renaming = nil
                    load()
                }
            )
            .transition(.opacity)
            .zIndex(1)
        }
    }
}

#Preview("CategoryView") {
    NavigationStack {
        CategoryView().environmentObject(DatabaseManager.shared)
    }
}
