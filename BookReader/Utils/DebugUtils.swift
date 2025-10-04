import Foundation
import SwiftUI
import os

/// 日志分类
enum LogCategory: String {
    case general
    case network
    case ui
    case database
    case auth
    case debug
    case importer
    case reader
    case pagination
    case prefetch
    case performance
}

/// 日志工具
enum Log {
    /// 获取指定分类的 Logger
    private static func logger(for category: LogCategory) -> Logger {
        Logger(subsystem: "net.zgia.bookreader", category: category.rawValue)
    }

    /// Debug 日志（受 AppSettings 控制）
    static func debug(_ message: String, category: LogCategory = .debug) {
        if AppSettings.shared.isLoggerEnabled() {
            logger(for: category).debug("\(message, privacy: .public)")
        }
    }

    /// Info 日志
    static func info(_ message: String, category: LogCategory = .general) {
        if AppSettings.shared.isLoggerEnabled() {
            logger(for: category).info("\(message, privacy: .public)")
        }
    }

    /// Warning 日志
    static func warning(_ message: String, category: LogCategory = .general) {
        if AppSettings.shared.isLoggerEnabled() {
            logger(for: category).warning("\(message, privacy: .public)")
        }
    }

    /// Error 日志
    static func error(_ message: String, category: LogCategory = .general) {
        if AppSettings.shared.isLoggerEnabled() {
            logger(for: category).error("\(message, privacy: .public)")
        }
    }
}

/// 简易性能计时器
struct PerfTimer {
    let name: String
    let category: LogCategory
    private let start: DispatchTime
    private let startDate: Date

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    init(_ name: String, category: LogCategory) {
        self.name = name
        self.category = category
        self.start = .now()
        self.startDate = Date()
    }

    func end(extra: String? = nil) {
        let endDispatch = DispatchTime.now()
        let endDate = Date()
        let elapsedNs = endDispatch.uptimeNanoseconds &- start.uptimeNanoseconds
        let elapsedMs = Double(elapsedNs) / 1_000_000.0
        let suffix = extra.map { " " + $0 } ?? ""
        let startStr = PerfTimer.timeFormatter.string(from: startDate)
        let endStr = PerfTimer.timeFormatter.string(from: endDate)
        Log.debug(
            "⏱️ \(name) \(String(format: "%.2f", elapsedMs))ms [\(startStr) → \(endStr)]\(suffix)",
            category: category
        )
    }
}

struct DebugUtils {
    static func printSandboxPaths() {
        let fm = FileManager.default

        if let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)
            .first
        {
            Log.info("📂 Documents: \(documents.path)", category: .database)

            // 直接告诉数据库应该放置的位置
            let dbURL = documents.appendingPathComponent("novel.sqlite")
            Log.info(
                "📌 你的 novel.sqlite 数据库应该放在这里: \(dbURL.path)",
                category: .database
            )
        }

        if let library = fm.urls(for: .libraryDirectory, in: .userDomainMask)
            .first
        {
            Log.info("📂 Library: \(library.path)")
        }

        if let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)
            .first
        {
            Log.info("📂 Caches: \(caches.path)")
        }

        if let appSupport = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            Log.info("📂 Application Support: \(appSupport.path)")
        }

        Log.info("🖥️ Temporary directory: \(NSTemporaryDirectory())")
    }
}
