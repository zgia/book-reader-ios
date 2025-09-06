import Foundation
import GRDB

extension DatabaseManager {
    // 书籍行记录，用于 SQL 结果映射
    struct BookRowRecord: Decodable, FetchableRecord {
        let id: Int
        let title: String
        let author: String?
        let category: String?
        let latest: String?
        let wordcount: Int?
        let isfinished: Int?
        let updatedat: Int?
    }

    // 书籍列表（带分类名 & 进度）
    func fetchBooks(search: String?, progressStore: ProgressStore) -> [BookRow]
    {
        let records: [BookRowRecord] =
            (try? dbQueue.read { db in
                var sql = """
                        SELECT b.id, b.title, a.name AS author, c.title AS category,
                               b.latest, b.wordcount, b.isfinished, b.updatedat
                        FROM book b
                        LEFT JOIN category c ON c.id = b.categoryid
                        LEFT JOIN book_author a ON a.id = b.authorid
                    """
                var args: [DatabaseValueConvertible] = []

                if let q = search, !q.isEmpty {
                    sql +=
                        " WHERE b.title LIKE ? ESCAPE '\\' OR a.name LIKE ? ESCAPE '\\'"
                    // 转义 % 和 _
                    let like =
                        "%\(q.replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_"))%"
                    args.append(like)
                    args.append(like)
                }

                sql += " ORDER BY b.updatedat DESC"

                return try BookRowRecord.fetchAll(
                    db,
                    sql: sql,
                    arguments: StatementArguments(args)
                )
            }) ?? []

        // 一次性获取所有 progress，避免 N+1 查询
        let progressDict = progressStore.allProgress()

        return records.map { r in
            let book = Book(
                id: r.id,
                category: r.category ?? "",
                title: r.title,
                author: r.author ?? "",
                latest: r.latest ?? "",
                wordcount: r.wordcount ?? 0,
                isfinished: r.isfinished ?? 0,
                updatedat: r.updatedat ?? 0
            )
            return BookRow(
                book: book,
                categoryTitle: r.category ?? "",
                lastProgress: progressDict[r.id]
            )
        }
    }

    func fetchChapters(bookId: Int, search: String?) -> [Chapter] {
        (try? dbQueue.read { db in
            var request = Chapter.filter(Column("bookid") == bookId).order(
                Column("id")
            )
            if let q = search, !q.isEmpty {
                request = request.filter(Column("title").like("%\(q)%"))
            }
            return try request.fetchAll(db)
        }) ?? []
    }

    func fetchContent(chapterId: Int) -> Content? {
        (try? dbQueue.read { db in
            try Content.fetchOne(db, key: chapterId)
        }) ?? nil
    }

    // 统计：某章节之后（不含该章节）剩余未读章数
    func unreadChapterCount(bookId: Int, afterChapterId chapterId: Int) -> Int {
        (try? dbQueue.read { db in
            try Chapter
                .filter(Column("bookid") == bookId && Column("id") > chapterId)
                .fetchCount(db)
        }) ?? 0
    }

    // 统计：本书总章节数
    func totalChapterCount(bookId: Int) -> Int {
        (try? dbQueue.read { db in
            try Chapter
                .filter(Column("bookid") == bookId)
                .fetchCount(db)
        }) ?? 0
    }

    // 将某本书的 updatedat 触达为当前时间戳
    func touchBookUpdatedAt(bookId: Int, at timestamp: Int? = nil) {
        let ts = timestamp ?? Int(Date().timeIntervalSince1970)
        guard let dbQueue = dbQueue else { return }
        do {
            try dbQueue.write { db in
                try db.execute(
                    sql: "UPDATE book SET updatedat = ? WHERE id = ?",
                    arguments: [ts, bookId]
                )
            }
        } catch {
            // 静默失败即可
        }
    }

    // 更新书名
    func updateBookTitle(bookId: Int, title: String) {
        guard let dbQueue = dbQueue else { return }
        let newTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newTitle.isEmpty else { return }
        do {
            try dbQueue.write { db in
                try db.execute(
                    sql:
                        "UPDATE book SET title = ?, updatedat = ? WHERE id = ?",
                    arguments: [
                        newTitle, Int(Date().timeIntervalSince1970), bookId,
                    ]
                )
            }
        } catch {
            // 静默失败即可
        }
    }

    // 删除整本书及其相关数据：content、chapter、volume、book
    func deleteBook(bookId: Int) {
        guard let dbQueue = dbQueue else { return }
        do {
            try dbQueue.write { db in
                // 先删除内容表中属于该书的章节内容
                try db.execute(
                    sql:
                        "DELETE FROM content WHERE chapterid IN (SELECT id FROM chapter WHERE bookid = ?)",
                    arguments: [bookId]
                )
                // 删除章节
                try db.execute(
                    sql: "DELETE FROM chapter WHERE bookid = ?",
                    arguments: [bookId]
                )
                // 删除分卷
                try db.execute(
                    sql: "DELETE FROM volume WHERE bookid = ?",
                    arguments: [bookId]
                )
                // 最后删除书籍
                try db.execute(
                    sql: "DELETE FROM book WHERE id = ?",
                    arguments: [bookId]
                )
            }
            // 删除完成后做轻量压缩（异步执行，不阻塞 UI）
            compactDatabase(hard: true)
        } catch {
            // 静默失败即可
        }
    }
}
