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

    // 统一：阅读进度文案（可附带百分比）
    func readingProgressText(
        forBookId bookId: Int,
        progressStore: ProgressStore,
        includePercent: Bool = false
    ) -> String {
        guard let last = progressStore.lastProgress(forBook: bookId) else {
            return includePercent ? "0%・未读" : "未读"
        }

        let unread = unreadChapterCount(
            bookId: bookId,
            afterChapterId: last.chapterId
        )
        let total = totalChapterCount(bookId: bookId)
        var percentValue: Double = 0
        if total > 0 {
            // 已完成的整章数 = 总章数 -（最后进度章及其之后章节数）
            let completedChapters = max(0, total - unread - 1)
            percentValue =
                (Double(completedChapters) + last.percent)
                / Double(max(1, total))
        }
        let percentText = "\(Int(round(percentValue * 100)))%"

        let base = unread == 0 ? "读完" : "\(unread)章未读"
        return includePercent ? "\(percentText)・\(base)" : base
    }

    // 书籍列表（带分类名 & 进度）
    // 可按分类筛选；当未指定分类时，自动过滤隐藏分类（ishidden = 1）
    func fetchBooks(
        search: String?,
        progressStore: ProgressStore,
        categoryId: Int? = nil
    ) -> [BookRow] {
        let records: [BookRowRecord] =
            (try? dbQueue.read { db in
                var sql = """
                        SELECT b.id, b.title, a.name AS author, c.title AS category,
                               b.latest, b.wordcount, b.isfinished, b.updatedat
                        FROM book b
                        LEFT JOIN category c ON c.id = b.categoryid
                        LEFT JOIN author a ON a.id = b.authorid
                    """
                var args: [DatabaseValueConvertible] = []

                var whereClauses: [String] = []
                if let q = search, !q.isEmpty {
                    whereClauses.append(
                        "(b.title LIKE ? ESCAPE '\\' OR a.name LIKE ? ESCAPE '\\')"
                    )
                    let like =
                        "%\(q.replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_"))%"
                    args.append(like)
                    args.append(like)
                }
                if let cid = categoryId {
                    whereClauses.append("b.categoryid = ?")
                    args.append(cid)
                    // 指定分类时，仍遵循隐藏策略：隐藏分类不显示
                    whereClauses.append("IFNULL(c.ishidden, 0) = 0")
                } else {
                    // 未指定分类时，排除隐藏分类
                    whereClauses.append("IFNULL(c.ishidden, 0) = 0")
                }
                if !whereClauses.isEmpty {
                    sql += " WHERE " + whereClauses.joined(separator: " AND ")
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
            compactDatabase(hard: false)
        } catch {
            // 静默失败即可
        }
    }

    // 收藏行记录（用于联表查询章节标题）
    struct FavoriteRowRecord: Decodable, FetchableRecord {
        let id: Int
        let bookid: Int
        let chapterid: Int
        let pageindex: Int?
        let percent: Double?
        let excerpt: String?
        let createdat: Int
        let chapterTitle: String?
    }

    // 查询：某本书的收藏列表（按创建时间倒序）
    func fetchFavorites(bookId: Int) -> [FavoriteRow] {
        let records: [FavoriteRowRecord] =
            (try? dbQueue.read { db in
                try FavoriteRowRecord.fetchAll(
                    db,
                    sql: """
                            SELECT f.id, f.bookid, f.chapterid, f.pageindex, f.percent, f.excerpt, f.createdat,
                                   c.title AS chapterTitle
                            FROM favorite f
                            LEFT JOIN chapter c ON c.id = f.chapterid
                            WHERE f.bookid = ?
                            ORDER BY f.createdat DESC, f.id DESC
                        """,
                    arguments: [bookId]
                )
            }) ?? []

        return records.map { r in
            let fav = Favorite(
                id: r.id,
                bookid: r.bookid,
                chapterid: r.chapterid,
                pageindex: r.pageindex,
                percent: r.percent,
                excerpt: r.excerpt,
                createdat: r.createdat
            )
            return FavoriteRow(
                favorite: fav,
                chapterTitle: r.chapterTitle ?? ""
            )
        }
    }

    // 新增：添加收藏，返回收藏 id
    @discardableResult
    func insertFavorite(
        bookId: Int,
        chapterId: Int,
        pageIndex: Int?,
        percent: Double?,
        excerpt: String?
    ) -> Int? {
        guard let dbQueue = dbQueue else { return nil }
        do {
            var newId: Int = 0
            try dbQueue.write { db in
                newId = try nextId("favorite", in: db)
                let ts = Int(Date().timeIntervalSince1970)
                try db.execute(
                    sql:
                        "INSERT INTO favorite(id, bookid, chapterid, pageindex, percent, excerpt, createdat) VALUES(:id, :bookid, :chapterid, :pageindex, :percent, :excerpt, :createdat)",
                    arguments: StatementArguments([
                        "id": newId,
                        "bookid": bookId,
                        "chapterid": chapterId,
                        "pageindex": pageIndex,
                        "percent": percent,
                        "excerpt": excerpt,
                        "createdat": ts,
                    ])
                )
            }
            return newId
        } catch {
            return nil
        }
    }

    // 删除：根据 id 删除收藏
    func deleteFavorite(id: Int) {
        guard let dbQueue = dbQueue else { return }
        do {
            try dbQueue.write { db in
                try db.execute(
                    sql: "DELETE FROM favorite WHERE id = ?",
                    arguments: [id]
                )
            }
        } catch {
            // 静默失败
        }
    }

    // MARK: - 分类
    func fetchCategories(includeHidden: Bool = false) -> [Category] {
        (try? dbQueue.read { db in
            var sql =
                "SELECT id, title, IFNULL(ishidden, 0) AS ishidden FROM category"
            if !includeHidden {
                sql += " WHERE IFNULL(ishidden, 0) = 0"
            }
            sql += " ORDER BY id ASC"
            return try Category.fetchAll(db, sql: sql)
        }) ?? []
    }

    @discardableResult
    func insertCategory(title: String) -> Int? {
        guard let dbQueue = dbQueue else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            var newId: Int = 0
            try dbQueue.write { db in
                newId = try nextId("category", in: db)
                try db.execute(
                    sql:
                        "INSERT INTO category(id, parentid, title, ishidden) VALUES(?, 0, ?, 0)",
                    arguments: [newId, trimmed]
                )
            }
            return newId
        } catch {
            return nil
        }
    }

    func updateCategoryTitle(id: Int, title: String) {
        guard let dbQueue = dbQueue else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try dbQueue.write { db in
                try db.execute(
                    sql: "UPDATE category SET title = ? WHERE id = ?",
                    arguments: [trimmed, id]
                )
            }
        } catch {
        }
    }

    func updateCategoryHidden(id: Int, isHidden: Bool) {
        guard let dbQueue = dbQueue else { return }
        do {
            try dbQueue.write { db in
                try db.execute(
                    sql: "UPDATE category SET ishidden = ? WHERE id = ?",
                    arguments: [isHidden ? 1 : 0, id]
                )
            }
        } catch {
        }
    }

    func deleteCategory(id: Int) {
        guard let dbQueue = dbQueue else { return }
        do {
            try dbQueue.write { db in
                // 将该分类下书籍的分类重置为 0（未分类）
                try db.execute(
                    sql: "UPDATE book SET categoryid = 0 WHERE categoryid = ?",
                    arguments: [id]
                )
                try db.execute(
                    sql: "DELETE FROM category WHERE id = ?",
                    arguments: [id]
                )
            }
        } catch {
        }
    }
}
