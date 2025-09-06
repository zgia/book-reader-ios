import Foundation
import GRDB

enum TxtImportError: LocalizedError {
    case missingTitle

    var errorDescription: String? {
        switch self {
        case .missingTitle:
            return "未解析到书名，请检查TXT文件格式（例如首行包含：书名：xxx）"
        }
    }
}

final class TxtBookImporter {
    private let dbManager: DatabaseManager

    init(dbManager: DatabaseManager = .shared) {
        self.dbManager = dbManager
    }

    func importTxt(at fileURL: URL) throws {
        try dbManager.ensureDatabaseReadyForImport()

        let text: String = try Self.readWholeText(fileURL: fileURL)

        let lines: [String] = text.split(whereSeparator: { $0.isNewline }).map {
            String($0)
        }

        // 预检测：必须能解析到书名
        let detected = Self.detectTitleAndAuthor(from: lines)
        guard let presetTitle = detected.title, !presetTitle.isEmpty else {
            throw TxtImportError.missingTitle
        }

        let volumeRegex = try NSRegularExpression(
            pattern: "^第([一二三四五六七八九十百零〇两\\d]+)卷[ \t]*(\\S.*)$"
        )
        let chapterRegex = try NSRegularExpression(
            pattern: "^第([一二三四五六七八九十百零〇两\\d]+)章[ \t]*(\\S.*)$"
        )

        let bookTitle: String? = detected.title
        let authorName: String? = detected.author

        var bookId: Int?
        var authorId: Int?
        var currentVolumeId: Int?

        var currentChapterId: Int?
        var currentChapterTitle: String = ""
        var currentChapterBuffer: [String] = []

        var lastChapterTitle: String = ""
        var totalWordCount: Int = 0

        try dbManager.dbQueue.write { db in
            // 预扫描已拿到书名/作者时，先创建作者与书，避免循环中再次处理
            if bookId == nil {
                if authorId == nil {
                    authorId = try dbManager.findOrCreateAuthorId(
                        name: authorName,
                        in: db
                    )
                }
                bookId = try dbManager.insertBook(
                    title: bookTitle ?? "",
                    authorId: authorId ?? 0,
                    in: db
                )
            }

            // 为了性能，整个导入在一个事务中完成
            for rawLine in lines {
                let line = rawLine

                // 匹配卷（必须行首无空格）
                if Self.matches(regex: volumeRegex, in: line) {
                    // 落当前章节
                    if let chapterId = currentChapterId, bookId != nil {
                        let contentText = currentChapterBuffer.joined(
                            separator: "\n"
                        )
                        try dbManager.insertContent(
                            chapterId: chapterId,
                            text: contentText,
                            in: db
                        )
                        lastChapterTitle = currentChapterTitle
                        totalWordCount += contentText.count
                        currentChapterBuffer.removeAll(keepingCapacity: true)
                        currentChapterId = nil
                    }
                    // 新卷
                    if let bid = bookId {
                        let title = line.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        currentVolumeId = try dbManager.insertVolume(
                            bookId: bid,
                            title: title,
                            in: db
                        )
                    }
                    continue
                }

                // 匹配章（必须行首无空格）
                if Self.matches(regex: chapterRegex, in: line) {
                    // 落上一章
                    if let chapterId = currentChapterId {
                        let contentText = currentChapterBuffer.joined(
                            separator: "\n"
                        )
                        try dbManager.insertContent(
                            chapterId: chapterId,
                            text: contentText,
                            in: db
                        )
                        lastChapterTitle = currentChapterTitle
                        totalWordCount += contentText.count
                        currentChapterBuffer.removeAll(keepingCapacity: true)
                    }
                    // 确保有卷
                    if currentVolumeId == nil, let bid = bookId {
                        currentVolumeId = try dbManager.insertVolume(
                            bookId: bid,
                            title: "正文",
                            in: db
                        )
                    }
                    // 新章
                    if let bid = bookId, let vid = currentVolumeId {
                        let title = line.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        currentChapterTitle = title
                        currentChapterId = try dbManager.insertChapter(
                            bookId: bid,
                            volumeId: vid,
                            title: title,
                            in: db
                        )
                    }
                    continue
                }

                // 普通内容行
                if currentChapterId != nil {
                    currentChapterBuffer.append(line)
                } else {
                    // 在没有进入任何章节前的内容，忽略或可作为卷/章前言。这里忽略。
                }
            }

            // 文件结束，落最后一章
            if let chapterId = currentChapterId {
                let contentText = currentChapterBuffer.joined(separator: "\n")
                try dbManager.insertContent(
                    chapterId: chapterId,
                    text: contentText,
                    in: db
                )
                lastChapterTitle = currentChapterTitle
                totalWordCount += contentText.count
            }

            // 更新书的 latest/wordcount/updatedat
            if let bid = bookId {
                try db.execute(
                    sql:
                        "UPDATE book SET latest = ?, wordcount = ?, updatedat = ? WHERE id = ?",
                    arguments: [
                        lastChapterTitle, totalWordCount,
                        Int(Date().timeIntervalSince1970), bid,
                    ]
                )
            }
        }
    }

    // 仅预览解析，不写入数据库
    func importTxtPreview(at fileURL: URL) throws {
        let text: String = try Self.readWholeText(fileURL: fileURL)

        let lines: [String] = text.split(whereSeparator: { $0.isNewline }).map {
            String($0)
        }

        // 预检测：必须能解析到书名
        let detected = Self.detectTitleAndAuthor(from: lines)
        guard let presetTitle = detected.title, !presetTitle.isEmpty else {
            throw TxtImportError.missingTitle
        }

        let volumeRegex = try NSRegularExpression(
            pattern: "^第([一二三四五六七八九十百零〇两\\d]+)卷[ \t]*(\\S.*)$"
        )
        let chapterRegex = try NSRegularExpression(
            pattern: "^第([一二三四五六七八九十百零〇两\\d]+)章[ \t]*(\\S.*)$"
        )

        // 优先打印预检测到的书名/作者（若后续遇到相同内容则跳过）
        print("书名: \(presetTitle)")
        if let a = detected.author, !a.isEmpty {
            print("作者: \(a)")
        }

        for rawLine in lines {
            let line = rawLine

            if Self.matches(regex: volumeRegex, in: line) {
                let title = line.trimmingCharacters(in: .whitespacesAndNewlines)
                print("卷: \(title)")
                continue
            }
            if Self.matches(regex: chapterRegex, in: line) {
                let title = line.trimmingCharacters(in: .whitespacesAndNewlines)
                print("章: \(title)")
                continue
            }
        }
    }

    // 预扫描标题与作者
    private static func detectTitleAndAuthor(from lines: [String]) -> (
        title: String?, author: String?
    ) {
        let titleRegex = try! NSRegularExpression(
            pattern: "^书名[:：]\\s*《?(.+?)》?\\s*$"
        )
        let authorRegex = try! NSRegularExpression(
            pattern: "^作者[:：]\\s*(.+?)\\s*$"
        )
        var title: String? = nil
        var author: String? = nil
        for line in lines.prefix(10) {
            if title == nil,
                let m = titleRegex.firstMatch(
                    in: line,
                    options: [],
                    range: NSRange(
                        location: 0,
                        length: (line as NSString).length
                    )
                ),
                let r = Range(m.range(at: 1), in: line)
            {
                title = String(line[r]).trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            }
            if author == nil,
                let m = authorRegex.firstMatch(
                    in: line,
                    options: [],
                    range: NSRange(
                        location: 0,
                        length: (line as NSString).length
                    )
                ),
                let r = Range(m.range(at: 1), in: line)
            {
                author = String(line[r]).trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            }
            if title != nil && author != nil { break }
        }
        return (title, author)
    }

    private static func readWholeText(fileURL: URL) throws -> String {
        // 优先 UTF-8，失败后尝试自动编码检测（NSString）
        if let text = try? String(contentsOf: fileURL, encoding: .utf8) {
            return text
        }
        let nsText =
            try NSString(contentsOf: fileURL, usedEncoding: nil) as String
        return nsText
    }

    private static func matches(regex: NSRegularExpression, in line: String)
        -> Bool
    {
        let ns = line as NSString
        if ns.length == 0 { return false }
        return regex.firstMatch(
            in: line,
            options: [],
            range: NSRange(location: 0, length: ns.length)
        ) != nil
    }

    private static func capture(
        regex: NSRegularExpression,
        in line: String,
        group: Int
    ) -> String? {
        let ns = line as NSString
        guard
            let m = regex.firstMatch(
                in: line,
                options: [],
                range: NSRange(location: 0, length: ns.length)
            )
        else { return nil }
        let r = m.range(at: group)
        if r.location != NSNotFound, let rr = Range(r, in: line) {
            return String(line[rr])
        }
        return nil
    }
}
