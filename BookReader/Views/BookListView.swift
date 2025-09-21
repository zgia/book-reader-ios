import GRDB
import SwiftUI

struct BookListView: View {
    @EnvironmentObject private var db: DatabaseManager
    @EnvironmentObject var progressStore: ProgressStore
    @EnvironmentObject private var appAppearance: AppAppearanceSettings
    @State private var books: [BookRow] = []
    @State private var searchText = ""
    @State private var searchDebounceTask: Task<Void, Never>? = nil
    @State private var renamingBook: BookRow? = nil
    @State private var newTitleText: String = ""
    @State private var deletingBook: BookRow? = nil
    @State private var showDeleteConfirm: Bool = false

    var body: some View {
        Group {
            if db.dbQueue == nil {
                VStack(spacing: 12) {
                    if let err = db.initError, !err.isEmpty {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 36))
                            .foregroundColor(.orange)
                        Text(err)
                            .multilineTextAlignment(.center)
                    } else {
                        ProgressView()
                        Text(String(localized: "db.initializing"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
            } else {
                NavigationStack {
                    List(books) { bookRow in
                        NavigationLink {
                            if let startChapter = startingChapter(for: bookRow)
                            {
                                ReaderView(chapter: startChapter)
                            } else {
                                VStack(spacing: 12) {
                                    Text(
                                        String(
                                            localized:
                                                "reading.chapter_not_fund"
                                        )
                                    )
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                            }
                        } label: {
                            VStack(alignment: .leading) {
                                Text(bookRow.book.title).font(.headline)
                                let authorText = makeAuthorText(
                                    bookRow: bookRow
                                )
                                if !authorText.isEmpty {
                                    Text(authorText)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                // 书籍额外信息：最新章节、总字数、完本状态
                                HStack(spacing: 8) {
                                    let chapterText = makeChapterText(
                                        bookRow: bookRow
                                    )
                                    if !chapterText.isEmpty {
                                        Text(chapterText)
                                    }
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                        }
                        .swipeActions(
                            edge: .trailing,
                            allowsFullSwipe: false
                        ) {
                            Button(role: .destructive) {
                                deletingBook = bookRow
                                showDeleteConfirm = true
                            } label: {
                                Image(systemName: "trash")
                            }
                            Button() {
                                renamingBook = bookRow
                                newTitleText = bookRow.book.title
                            }
                            label: {
                                Image(systemName: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                    .animation(.default, value: books)
                    .searchable(text: $searchText)
                    .onChange(of: searchText) { oldValue, newValue in
                        // 防抖：避免输入法组合期间频繁刷新
                        searchDebounceTask?.cancel()
                        searchDebounceTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 300_000_000)  // 0.3s
                            loadBooks(search: newValue)
                        }
                    }
                    .navigationTitle(String(localized: "book"))
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            NavigationLink(destination: AppSettingsView()) {
                                Image(systemName: "gear")
                            }
                        }
                    }
                    .onAppear {
                        loadBooks(search: searchText)
                        // 监听取消模态视图的通知
                        NotificationCenter.default.addObserver(
                            forName: .dismissAllModals,
                            object: nil,
                            queue: .main
                        ) { _ in
                            showDeleteConfirm = false
                            renamingBook = nil
                        }
                    }
                    .onDisappear {
                        // 移除通知监听器
                        NotificationCenter.default.removeObserver(self)
                    }
                    // 基于目的地闭包的导航，已不再使用基于值的目的地
                    .overlay {
                        if let renaming = renamingBook {
                            TextFieldDialog(
                                title: String(localized: "book.renaming_title"),
                                placeholder: String(
                                    localized: "book.renaming_new_name"
                                ),
                                text: $newTitleText,
                                onCancel: { renamingBook = nil },
                                onSave: {
                                    let trimmed =
                                        newTitleText.trimmingCharacters(
                                            in: .whitespacesAndNewlines
                                        )
                                    guard !trimmed.isEmpty else {
                                        renamingBook = nil
                                        return
                                    }
                                    db.updateBookTitle(
                                        bookId: renaming.book.id,
                                        title: trimmed
                                    )
                                    loadBooks(search: searchText)
                                    renamingBook = nil
                                }
                            )
                            .transition(.opacity)
                            .zIndex(1)
                        }
                    }
                    .confirmationDialog(
                        String(localized: "book.confirm_deleting"),
                        isPresented: $showDeleteConfirm,
                        presenting: deletingBook
                    ) { target in
                        Button(
                            String(localized: "btn_delete"),
                            role: .destructive
                        ) {
                            withAnimation {
                                db.deleteBook(bookId: target.book.id)
                                progressStore.clear(forBook: target.book.id)
                                loadBooks(search: searchText)
                                deletingBook = nil
                            }
                        }
                        Button(String(localized: "btn_cancel"), role: .cancel) {
                            deletingBook = nil
                        }
                    } message: { target in
                        Text(
                            String(
                                format: String(
                                    localized: "book.confirm_deleting_message"
                                ),
                                target.book.title
                            )
                        )
                    }
                    .onChange(of: showDeleteConfirm) { _, newValue in
                        if !newValue { deletingBook = nil }
                    }
                }
            }
        }
    }

    private func loadBooks(search: String? = nil) {
        books = db.fetchBooks(
            search: search?.isEmpty == true ? nil : search,
            progressStore: progressStore
        )
    }

    // 计算进入阅读时的起始章节：优先使用上次进度，否则为第一章
    private func startingChapter(for bookRow: BookRow) -> Chapter? {
        guard let dbQueue = db.dbQueue else { return nil }
        if let last = bookRow.lastProgress {
            if let chapter = try? dbQueue.read({ db in
                try Chapter.filter(Column("id") == last.chapterId).fetchOne(db)
            }) {
                // 防御：仅当进度章节属于当前书时才采用
                if chapter.bookid == bookRow.book.id {
                    return chapter
                }
            }
        }
        // 无进度或进度章节不匹配/不存在时，取第一章
        return try? dbQueue.read { db in
            try Chapter.filter(Column("bookid") == bookRow.book.id)
                .order(Column("id"))
                .fetchOne(db)
        }
    }

    // 列表展示的阅读进度文案（含百分比）
    private func progressText(for book: Book) -> String {
        db.readingProgressText(
            forBookId: book.id,
            progressStore: progressStore,
            includePercent: true
        )
    }

    // 组合分类与进度为单行文案
    private func makeAuthorText(bookRow: BookRow) -> String {
        let progress = progressText(for: bookRow.book)

        var parts: [String] = []
        // if !bookRow.categoryTitle.isEmpty { parts.append(bookRow.categoryTitle) }
        if !bookRow.book.author.isEmpty { parts.append(bookRow.book.author) }
        if !progress.isEmpty { parts.append(progress) }

        return parts.joined(separator: "・")
    }

    // 组合最新章节和完本信息为单行文案
    private func makeChapterText(bookRow: BookRow) -> String {

        var parts: [String] = []

        // if !bookRow.book.wordcount.isEmpty { parts.append(bookRow.book.wordcount) }
        if bookRow.book.isfinished == 1 {
            parts.append(String(localized: "bookinfo.finished"))
        }
        if !bookRow.book.latest.isEmpty { parts.append(bookRow.book.latest) }

        return parts.joined(separator: "・")
    }
}

#Preview("BookListView") {
    BookListView()
        .environmentObject(DatabaseManager.shared)
        .environmentObject(ProgressStore())
}
