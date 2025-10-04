import SwiftUI
import os

struct Paginator {
    static func paginate(
        text: String,
        fontSize: Double,
        screen: CGSize,
        lineSpacing: Double
    ) -> [String] {
        let perf = PerfTimer("paginate", category: .pagination)
        let totalChars = text.count
        Log.debug(
            "📄 paginate start chars=\(totalChars) font=\(fontSize) screen=\(Int(screen.width))x\(Int(screen.height)) lineSpacing=\(lineSpacing)",
            category: .pagination
        )
        // 经验性容量估计：
        // 每行字符 ~ screen.width / (fontSize * 0.55)
        // 每屏行数 ~ screen.height / (fontSize * 1.6)
        let charsPerLine = max(10, Int(screen.width / (fontSize * 0.55)))
        let linesPerPage = max(8, Int(screen.height / (fontSize * 1.6)))
        let charsPerPage = max(300, charsPerLine * linesPerPage)

        var pages: [String] = []
        var start = text.startIndex
        while start < text.endIndex {
            let end =
                text.index(
                    start,
                    offsetBy: charsPerPage,
                    limitedBy: text.endIndex
                ) ?? text.endIndex
            // 尽量在段落边界截断
            var cut = end
            if end < text.endIndex,
                let range = text[start..<end].lastIndex(of: "\n")
            {
                cut = range
            }
            pages.append(String(text[start..<cut]))
            start = cut == end ? end : text.index(after: cut)
        }
        let result = pages.isEmpty ? [text] : pages
        perf.end(extra: "pages=\(result.count) charsPerPage≈\(charsPerPage)")
        return result
    }
}
