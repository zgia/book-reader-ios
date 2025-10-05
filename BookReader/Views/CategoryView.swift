import SwiftUI

struct CategoryView: View {
    @EnvironmentObject private var db: DatabaseManager
    @EnvironmentObject private var appSettings: AppSettings

    @State private var categories: [Category] = []
    @State private var newTitle: String = ""
    @State private var renaming: Category? = nil
    @State private var renameText: String = ""
    @State private var bookCounts: [Int: Int] = [:]

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
                    Button(String(localized: "btn.add")) { addCategory() }
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
                            let icon = cat.ishidden == 1 ? "eye.slash" : "eye"
                            Image(systemName: icon)
                                .foregroundColor(.secondary)

                            VStack(alignment: .leading) {
                                let count = bookCounts[cat.id] ?? 0
                                let countText = String(
                                    format: String(
                                        localized: "category.book_count_x"
                                    ),
                                    count
                                )

                                Text(cat.title)
                                Text(countText)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Menu {
                                Button {
                                    renaming = cat
                                    renameText = cat.title
                                } label: {
                                    Label(
                                        String(localized: "btn.rename"),
                                        systemImage: "pencil"
                                    )
                                }
                                Button {
                                    db.updateCategoryHidden(
                                        id: cat.id,
                                        isHidden: cat.ishidden == 0
                                    )
                                    load()
                                } label: {
                                    Label(
                                        cat.ishidden == 1
                                            ? String(localized: "btn.show")
                                            : String(localized: "btn.hide"),
                                        systemImage: cat.ishidden == 1
                                            ? "eye"
                                            : "eye.slash"
                                    )
                                }
                                Divider()
                                Button(
                                    role: .destructive
                                ) {
                                    deleting = cat
                                } label: {
                                    Label(
                                        String(localized: "btn.delete"),
                                        systemImage: "trash"
                                    )
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
        .onChange(of: appSettings.isHidingHiddenCategoriesInManagement()) { _, _ in
            load()
        }
        .overlay(renamingOverlay())
        .alert(
            String(localized: "category.confirm_deleting"),
            isPresented: Binding(
                get: { deleting != nil },
                set: { if !$0 { deleting = nil } }
            )
        ) {
            Button(String(localized: "btn.cancel"), role: .cancel) {}
            Button(String(localized: "btn.delete"), role: .destructive) {
                if let target = deleting {
                    db.deleteCategory(id: target.id)
                    deleting = nil
                    load()
                }
            }
        } message: {
            if let target = deleting {
                Text(
                    String(
                        format: String(
                            localized: "category.confirm_deleting_x_message"
                        ),
                        target.title
                    )
                )
            } else {
                Text("")
            }
        }
    }

    private func load() {
        let includeHidden = !appSettings.isHidingHiddenCategoriesInManagement()
        categories = db.fetchCategories(includeHidden: includeHidden)
        bookCounts = db.fetchBookCountsByCategory()
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
                title: String(localized: "category.renaming_title"),
                placeholder: String(localized: "category.renaming_placeholder"),
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

    @State private var deleting: Category? = nil
}

#Preview("CategoryView") {
    NavigationStack {
        CategoryView().environmentObject(DatabaseManager.shared)
    }
}
