import SwiftUI

struct BookInfoView: View {

    let book: Book
    let progressText: String
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var db: DatabaseManager

    @State private var categoryTitle: String = ""
    @State private var currentCategoryId: Int? = nil
    @State private var categories: [Category] = []
    @State private var showingCategorySheet: Bool = false

    var body: some View {
        NavigationStack {
            List {
                Section(String(localized: "bookinfo.basic_info")) {
                    infoRow(
                        systemName: "book",
                        label: String(localized: "bookinfo.name"),
                        value: book.title
                    )
                    infoRow(
                        systemName: "person",
                        label: String(localized: "bookinfo.author"),
                        value: book.author
                    )
                    categoryEditableRow()
                    infoRow(
                        systemName: "textformat.123",
                        label: String(localized: "bookinfo.wordcount"),
                        value: WordCountFormatter.string(from: book.wordcount)
                    )
                    infoRow(
                        systemName: book.isfinished == 1
                            ? "checkmark.seal" : "clock",
                        label: String(localized: "bookinfo.status"),
                        value: book.isfinished == 1
                            ? String(localized: "bookinfo.finished")
                            : String(localized: "bookinfo.status_ongoing")
                    )
                    infoRow(
                        systemName: "calendar.badge.clock",
                        label: String(localized: "bookinfo.last_updated_at"),
                        value: formatDate(book.updatedat)
                    )
                    if !book.latest.isEmpty {
                        infoRow(
                            systemName: "list.bullet",
                            label: String(
                                localized: "bookinfo.latest_chapter"
                            ),
                            value: book.latest
                        )
                    }
                }

                Section(String(localized: "bookinfo.reading")) {
                    infoRow(
                        systemName: "percent",
                        label: String(localized: "bookinfo.reading_percent"),
                        value: progressText
                    )
                }
            }
            .navigationTitle(String(localized: "book_info.title"))
            //.toolbar {
            //    ToolbarItem(placement: .topBarTrailing) {
            //        Button(String(localized: "btn_done")) { dismiss() }
            //    }
            //}
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .navigationBarTitleDisplayMode(.inline)
            .presentationBackgroundInteraction(.enabled)
            .interactiveDismissDisabled(false)
            .onAppear {
                categoryTitle = book.category
                currentCategoryId = db.getBookCategoryId(bookId: book.id)
                categories = db.fetchCategories(includeHidden: false)
            }
            .sheet(isPresented: $showingCategorySheet) {
                NavigationStack {
                    List {
                        Button {
                            selectCategory(
                                nil,
                                title: String(localized: "category.all")
                            )
                        } label: {
                            HStack {
                                Text(String(localized: "category.all"))
                                Spacer()
                                if currentCategoryId == nil
                                    || currentCategoryId == 0
                                {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                        ForEach(categories) { cat in
                            Button {
                                selectCategory(cat.id, title: cat.title)
                            } label: {
                                HStack {
                                    Text(cat.title)
                                    Spacer()
                                    if currentCategoryId == cat.id {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                        }
                    }
                    .navigationTitle(String(localized: "bookinfo.set_category"))
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(String(localized: "btn_done")) {
                                showingCategorySheet = false
                            }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
    }

    @ViewBuilder
    private func infoRow(systemName: String, label: String, value: String)
        -> some View
    {
        HStack {
            Label {
                Text(label)
            } icon: {
                Image(systemName: systemName)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 16)
            Text(value)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }

    private func formatDate(_ ts: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ts))
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    @ViewBuilder
    private func categoryEditableRow() -> some View {
        Button {
            categories = db.fetchCategories(includeHidden: false)
            showingCategorySheet = true
        } label: {
            HStack {
                Label {
                    Text(String(localized: "bookinfo.category"))
                } icon: {
                    Image(systemName: "tag").foregroundColor(.secondary)
                }
                Spacer(minLength: 16)
                Text(displayedCategoryTitle())
                    .foregroundColor(.secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .font(.subheadline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "bookinfo.category"))
    }

    private func displayedCategoryTitle() -> String {
        if let cid = currentCategoryId, cid != 0 {
            if let found = categories.first(where: { $0.id == cid }) {
                return found.title
            }
            if !categoryTitle.isEmpty { return categoryTitle }
        }
        return String(localized: "category.all")
    }

    private func selectCategory(_ id: Int?, title: String) {
        currentCategoryId = (id ?? 0) == 0 ? nil : id
        db.updateBookCategory(bookId: book.id, categoryId: id)
        // 更新本地显示标题
        if let cid = id, let found = categories.first(where: { $0.id == cid }) {
            categoryTitle = found.title
        } else {
            categoryTitle = ""
        }
        showingCategorySheet = false
    }
}
