import Foundation
import GRDB

final class DatabaseManager: ObservableObject {
    static let shared = DatabaseManager()
    @Published var dbQueue: DatabaseQueue!
    @Published var needsDatabaseImport: Bool = false
    @Published var isCompacting: Bool = false

    init() {
        setupDatabase()
    }

    private func setupDatabase() {
        let fm = FileManager.default
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)
            .first!
        let dbURL = documents.appendingPathComponent("novel.sqlite")

        // 如果数据库文件不存在，提示用户导入
        guard fm.fileExists(atPath: dbURL.path) else {
            self.needsDatabaseImport = true
            return
        }

        do {
            var config = Configuration()
            config.prepareDatabase { db in
                try db.execute(sql: "PRAGMA journal_mode=WAL;")
                try db.execute(sql: "PRAGMA synchronous=NORMAL;")
                // 开启增量自动回收，配合 incremental_vacuum 使用
                try db.execute(sql: "PRAGMA auto_vacuum=INCREMENTAL;")
            }
            dbQueue = try DatabaseQueue(path: dbURL.path, configuration: config)
        } catch {
            fatalError("打开数据库失败: \(error)")
        }
    }

    // MARK: - Import helpers
    func ensureDatabaseReadyForImport() throws {
        // 若 dbQueue 未初始化（例如首次运行且用户未导入），则尝试在文档目录创建空库并初始化连接
        if dbQueue == nil {
            let fm = FileManager.default
            let documents = fm.urls(
                for: .documentDirectory,
                in: .userDomainMask
            )
            .first!
            let dbURL = documents.appendingPathComponent("novel.sqlite")
            if !fm.fileExists(atPath: dbURL.path) {
                // 创建空文件（GRDB 会初始化）
                fm.createFile(atPath: dbURL.path, contents: nil)
            }
            var config = Configuration()
            config.prepareDatabase { db in
                try db.execute(sql: "PRAGMA journal_mode=WAL;")
                try db.execute(sql: "PRAGMA synchronous=NORMAL;")
                try db.execute(sql: "PRAGMA auto_vacuum=INCREMENTAL;")
            }
            dbQueue = try DatabaseQueue(path: dbURL.path, configuration: config)
        }
        // 确保表结构存在（如果用户是空库）
        try dbQueue.write { db in
            // 最小建表，按 Resources/book.sql 的字段
            try db.execute(
                sql: """
                        CREATE TABLE IF NOT EXISTS book (
                            id         BIGINT,
                            categoryid BIGINT,
                            title      TEXT,
                            alias      TEXT,
                            authorid   BIGINT,
                            summary    TEXT,
                            source     TEXT,
                            latest     TEXT,
                            rate       BIGINT,
                            wordcount  BIGINT,
                            isfinished BIGINT,
                            cover      TEXT,
                            createdat  BIGINT,
                            updatedat  BIGINT,
                            deletedat  BIGINT
                        );
                    """
            )
            try db.execute(
                sql: """
                        CREATE TABLE IF NOT EXISTS book_author (
                            id          BIGINT,
                            name        TEXT,
                            former_name TEXT,
                            createdat   BIGINT,
                            updatedat   BIGINT,
                            deletedat   BIGINT
                        );
                    """
            )
            try db.execute(
                sql: """
                        CREATE TABLE IF NOT EXISTS category (
                            id       BIGINT,
                            parentid BIGINT,
                            title    TEXT
                        );
                    """
            )
            try db.execute(
                sql: """
                        CREATE TABLE IF NOT EXISTS volume (
                            id        BIGINT,
                            bookid    BIGINT,
                            title     TEXT,
                            summary   TEXT,
                            cover     TEXT,
                            createdat BIGINT,
                            updatedat BIGINT,
                            deletedat BIGINT
                        );
                    """
            )
            try db.execute(
                sql: """
                        CREATE TABLE IF NOT EXISTS chapter (
                            id        BIGINT,
                            bookid    BIGINT,
                            volumeid  BIGINT,
                            title     TEXT,
                            wordcount BIGINT,
                            createdat BIGINT,
                            updatedat BIGINT,
                            deletedat BIGINT
                        );
                    """
            )
            try db.execute(
                sql: """
                        CREATE TABLE IF NOT EXISTS content (
                            chapterid BIGINT,
                            txt       TEXT
                        );
                    """
            )
        }
        // 数据库已就绪，不再提示缺少导入
        DispatchQueue.main.async { [weak self] in
            self?.needsDatabaseImport = false
        }
    }

    func nextId(_ table: String, in db: Database) throws -> Int {
        let sql = "SELECT IFNULL(MAX(id), 0) + 1 FROM \(table)"
        return try Int.fetchOne(db, sql: sql) ?? 1
    }

    func findOrCreateAuthorId(name: String?, in db: Database) throws -> Int? {
        guard let n = name?.trimmingCharacters(in: .whitespacesAndNewlines),
            !n.isEmpty
        else { return nil }
        if let existing: Int = try Int.fetchOne(
            db,
            sql: "SELECT id FROM book_author WHERE name = ? LIMIT 1",
            arguments: [n]
        ) {
            return existing
        }
        let newId = try nextId("book_author", in: db)
        let ts = Int(Date().timeIntervalSince1970)
        try db.execute(
            sql:
                "INSERT INTO book_author(id, name, createdat, updatedat, deletedat) VALUES(?, ?, ?, ?, 0)",
            arguments: [newId, n, ts, ts]
        )
        return newId
    }

    func insertBook(title: String, authorId: Int, in db: Database) throws
        -> Int
    {
        if let existing: Int = try Int.fetchOne(
            db,
            sql:
                "SELECT id FROM book WHERE title = ? LIMIT 1",
            arguments: [title]
        ) {
            return existing
        }
        let newId = try nextId("book", in: db)
        let ts = Int(Date().timeIntervalSince1970)
        // 插入时若 authorId 为空，则写入 0
        let args: StatementArguments = [
            "id": newId,
            "title": title,
            "authorid": authorId,
            "created": ts,
            "updated": ts,
        ]
        try db.execute(
            sql:
                "INSERT INTO book(id, title, authorid, categoryid, summary, source, rate, wordcount, isfinished, createdat, updatedat, deletedat) VALUES(:id, :title, :authorid, 0, '', '', 0, 0, 0, :created, :updated, 0)",
            arguments: args
        )
        return newId
    }

    func updateBookAuthorId(bookId: Int, authorId: Int, in db: Database) throws
    {
        try db.execute(
            sql: "UPDATE book SET authorid = ?, updatedat = ? WHERE id = ?",
            arguments: [authorId, Int(Date().timeIntervalSince1970), bookId]
        )
    }

    func insertVolume(bookId: Int, title: String, in db: Database) throws -> Int
    {
        let newId = try nextId("volume", in: db)
        let ts = Int(Date().timeIntervalSince1970)
        try db.execute(
            sql:
                "INSERT INTO volume(id, bookid, title, summary, cover, createdat, updatedat, deletedat) VALUES(?, ?, ?, '','', ?, ?, 0)",
            arguments: [newId, bookId, title, ts, ts]
        )
        return newId
    }

    func insertChapter(
        bookId: Int,
        volumeId: Int,
        title: String,
        in db: Database
    ) throws -> Int {
        let newId = try nextId("chapter", in: db)
        let ts = Int(Date().timeIntervalSince1970)
        try db.execute(
            sql:
                "INSERT INTO chapter(id, bookid, volumeid, title, createdat, updatedat, deletedat) VALUES(?, ?, ?, ?, ?, ?, 0)",
            arguments: [newId, bookId, volumeId, title, ts, ts]
        )
        return newId
    }

    func insertContent(chapterId: Int, text: String, in db: Database) throws {
        try db.execute(
            sql: "INSERT INTO content(chapterid, txt) VALUES(?, ?)",
            arguments: [chapterId, text]
        )
        try db.execute(
            sql: "UPDATE chapter SET wordcount = ? WHERE id = ?",
            arguments: [text.count, chapterId]
        )
    }

    private func fromBundle() {
        let fm = FileManager.default

        // 沙盒存放数据库
        let appSupport = try! fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dbFolder = appSupport.appendingPathComponent(
            "db",
            isDirectory: true
        )
        try? fm.createDirectory(at: dbFolder, withIntermediateDirectories: true)
        let dstURL = dbFolder.appendingPathComponent("novel.sqlite")

        if !fm.fileExists(atPath: dstURL.path) {
            // 从 Package 资源复制数据库
            guard
                let srcURL = Bundle.main.url(
                    forResource: "novel",
                    withExtension: "sqlite"
                )
            else {
                fatalError("novel.sqlite 未加入 Package 资源或命名不一致")
            }
            do {
                try fm.copyItem(at: srcURL, to: dstURL)
            } catch {
                fatalError("复制数据库失败: \(error)")
            }
        }

        do {
            var config = Configuration()
            config.prepareDatabase { db in
                try db.execute(sql: "PRAGMA journal_mode=WAL;")
                try db.execute(sql: "PRAGMA synchronous=NORMAL;")
                try db.execute(sql: "PRAGMA auto_vacuum=INCREMENTAL;")
            }
            dbQueue = try DatabaseQueue(
                path: dstURL.path,
                configuration: config
            )
        } catch {
            fatalError("打开数据库失败: \(error)")
        }

    }

    // MARK: - 维护：压缩与回收空间
    /// 压缩数据库文件并回收空闲页。
    /// - Parameter hard: 为 true 时执行完整 VACUUM（最慢、回收最彻底）；
    ///                   为 false 时执行 checkpoint(TRUNCATE)+incremental_vacuum(0)（快、足够释放空闲页并截断 WAL）。
    func compactDatabase(hard: Bool = false, completion: (() -> Void)? = nil) {
        guard let dbQueue = dbQueue else { return }
        DispatchQueue.global(qos: .utility).async {
            DispatchQueue.main.async { [weak self] in self?.isCompacting = true
            }
            do {
                try dbQueue.inDatabase { db in
                    // 截断 WAL，避免 -wal 文件膨胀
                    try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE);")
                    // 确保使用增量回收模式
                    try db.execute(sql: "PRAGMA auto_vacuum=INCREMENTAL;")
                    if hard {
                        // 完整重建文件，释放到操作系统
                        try db.execute(sql: "VACUUM;")
                    } else {
                        // 回收所有 freelist 页到操作系统
                        try db.execute(sql: "PRAGMA incremental_vacuum(0);")
                    }
                }
            } catch {
                // 忽略清理失败
            }
            DispatchQueue.main.async { [weak self] in
                self?.isCompacting = false
                completion?()
            }
        }
    }

    // MARK: - 维护：统计信息
    struct DatabaseStats {
        let dbSize: Int64
        let walSize: Int64
        let shmSize: Int64
        let pageSize: Int
        let freelistCount: Int
        var estimatedReclaimableBytes: Int64 {
            Int64(pageSize) * Int64(freelistCount)
        }
        var totalSize: Int64 { dbSize + walSize + shmSize }
    }

    /// 获取当前数据库文件统计（主库、WAL、SHM）及可回收空间估算
    func getDatabaseStats() -> DatabaseStats? {
        let fm = FileManager.default
        guard
            let documents = fm.urls(
                for: .documentDirectory,
                in: .userDomainMask
            )
            .first
        else { return nil }
        let dbURL = documents.appendingPathComponent("novel.sqlite")
        let walURL = URL(fileURLWithPath: dbURL.path + "-wal")
        let shmURL = URL(fileURLWithPath: dbURL.path + "-shm")

        let dbSize =
            (try? fm.attributesOfItem(atPath: dbURL.path)[.size] as? NSNumber)?
            .int64Value ?? 0
        let walSize =
            (try? fm.attributesOfItem(atPath: walURL.path)[.size] as? NSNumber)?
            .int64Value ?? 0
        let shmSize =
            (try? fm.attributesOfItem(atPath: shmURL.path)[.size] as? NSNumber)?
            .int64Value ?? 0

        var pageSize: Int = 0
        var freelistCount: Int = 0
        if let dbQueue = dbQueue {
            do {
                try dbQueue.read { db in
                    pageSize =
                        (try Int.fetchOne(db, sql: "PRAGMA page_size;") ?? 0)
                    freelistCount =
                        (try Int.fetchOne(db, sql: "PRAGMA freelist_count;")
                            ?? 0)
                }
            } catch {
                // 忽略统计失败
            }
        }

        return DatabaseStats(
            dbSize: dbSize,
            walSize: walSize,
            shmSize: shmSize,
            pageSize: pageSize,
            freelistCount: freelistCount
        )
    }
}
