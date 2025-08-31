import Foundation
import GRDB

final class DatabaseManager: ObservableObject {
    static let shared = DatabaseManager()
    @Published var dbQueue: DatabaseQueue!
    @Published var needsDatabaseImport: Bool = false

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
            }
            dbQueue = try DatabaseQueue(path: dbURL.path, configuration: config)
        } catch {
            fatalError("打开数据库失败: \(error)")
        }
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
            }
            dbQueue = try DatabaseQueue(
                path: dstURL.path,
                configuration: config
            )
        } catch {
            fatalError("打开数据库失败: \(error)")
        }

    }
}
