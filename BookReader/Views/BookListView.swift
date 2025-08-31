import GRDB
import SwiftUI

struct BookListView: View {
    @EnvironmentObject private var db: DatabaseManager
    @EnvironmentObject var progressStore: ProgressStore
    @EnvironmentObject private var appAppearance: AppAppearanceSettings
    @State private var books: [BookRow] = []
    @State private var searchText = ""
    @State private var searchDebounceTask: Task<Void, Never>? = nil

    var body: some View {
        Group {
            if db.dbQueue == nil {
                // 数据库不存在时的提示
                Text("请连接手机到电脑，在 文件 → BookReader 文件夹 内放入 novel.sqlite")
                    .padding()
                    .multilineTextAlignment(.center)
            } else {
                NavigationStack {
                    List(books) { bookRow in
                        if let startChapter = startingChapter(for: bookRow) {
                            NavigationLink(value: startChapter) {
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
                        } else {
                            // 若没有可用章节，禁用跳转但仍显示条目
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
                                Text("无可阅读章节").font(.caption).foregroundColor(
                                    .secondary
                                )
                            }
                        }
                    }
                    .searchable(text: $searchText)
                    .onChange(of: searchText) { oldValue, newValue in
                        // 防抖：避免输入法组合期间频繁刷新
                        searchDebounceTask?.cancel()
                        searchDebounceTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 300_000_000)  // 0.3s
                            loadBooks(search: newValue)
                        }
                    }
                    .navigationTitle("书籍")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            NavigationLink(destination: AppSettingsView()) {
                                Image(systemName: "gear")
                            }
                        }
                    }
                    .onAppear { loadBooks(search: searchText) }
                    .navigationDestination(for: Chapter.self) { ch in
                        ReaderView(chapter: ch)
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

    // 列表展示的阅读进度文案
    private func progressText(for book: Book) -> String {
        if let last = progressStore.lastProgress(forBook: book.id) {
            let unread = db.unreadChapterCount(
                bookId: book.id,
                afterChapterId: last.chapterId
            )
            return unread == 0 ? "读完" : "\(unread)章未读"
        } else {
            return "未读"
        }
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
        if bookRow.book.isfinished == 1 { parts.append("完本") }
        if !bookRow.book.latest.isEmpty { parts.append(bookRow.book.latest) }

        return parts.joined(separator: "・")
    }
}

#Preview {
    BookListView()
        .environmentObject(DatabaseManager.shared)
        .environmentObject(ProgressStore())
}
