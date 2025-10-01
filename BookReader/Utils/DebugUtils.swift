import Foundation
import SwiftUI

struct DebugUtils {
    private static var isEnabled: Bool {
        UserDefaults.standard.bool(
            forKey: DefaultsKeys.readerDebugLoggingEnabled
        )
    }

    static func dlog(_ message: String) {
        if isEnabled {
            print(message)
        }
    }

    static func printSandboxPaths() {
        let fm = FileManager.default

        if let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)
            .first
        {
            print("📂 Documents: \(documents.path)")

            // 直接告诉数据库应该放置的位置
            let dbURL = documents.appendingPathComponent("novel.sqlite")
            print("📌 你的 novel.sqlite 数据库应该放在这里: \(dbURL.path)")
        }

        if let library = fm.urls(for: .libraryDirectory, in: .userDomainMask)
            .first
        {
            print("📂 Library: \(library.path)")
        }

        if let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)
            .first
        {
            print("📂 Caches: \(caches.path)")
        }

        if let appSupport = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            print("📂 Application Support: \(appSupport.path)")
        }

        print("🖥️ Temporary directory: \(NSTemporaryDirectory())")
    }
}
