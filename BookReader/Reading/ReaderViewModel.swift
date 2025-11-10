import Foundation
import GRDB
import SwiftUI

@MainActor
final class ReaderViewModel: ObservableObject {
    // MARK: - Dependencies
    var db: DatabaseManager?

    // MARK: - Published State (驱动 UI 的状态)
    @Published var currentBook: Book?
    @Published var currentChapter: Chapter
    @Published var content: Content?

    // 布局上下文（用于分页）
    @Published var screenSize: CGSize = .zero

    // MARK: - Caches and pagination
    // 当前章节的段落与分页数据
    @Published var paragraphs: [String] = []
    @Published var pages: [String] = []
    @Published var pagesParts: [[String]] = []

    // 章节级缓存，避免重复计算
    var paragraphsCache: [Int: [String]] = [:]  // chapterId -> paragraphs
    var contentCache: [Int: Content] = [:]  // chapterId -> content
    var pagesCache: [Int: [String]] = [:]  // chapterId -> pages
    var pagesPartsCache: [Int: [[String]]] = [:]  // chapterId -> [[paragraphs]]

    // MARK: - Chapter navigation
    @Published var prevChapterRef: Chapter?
    @Published var nextChapterRef: Chapter?
    @Published var prefetchRadius: Int = 1
    nonisolated static let prefetchSemaphore: DispatchSemaphore =
        DispatchSemaphore(value: 2)

    // MARK: - Restore state
    @Published var needsInitialRestore: Bool = true
    @Published var pendingRestorePercent: Double? = nil
    @Published var pendingRestorePageIndex: Int? = nil
    @Published var pendingRestoreChapterId: Int? = nil

    // MARK: - Touch throttle
    @Published var lastBookUpdatedAtTouchUnixTime: Int = 0

    // MARK: - Skeleton
    @Published var showInitialSkeleton: Bool = false

    // MARK: - LRU cache control
    let cacheCapacity: Int = 12
    private var cacheOrder: [Int] = []

    // MARK: - UI derived state
    @Published var currentVisiblePageIndex: Int = 0

    // MARK: - Init
    init(initialChapter: Chapter, isInitialFromBookList: Bool = false) {
        self.currentChapter = initialChapter
        self.showInitialSkeleton = isInitialFromBookList
    }

    // MARK: - Pagination config (快照用于后台线程)
    struct PaginationConfig {
        let screen: CGSize
        let fontSize: CGFloat
        let lineSpacing: CGFloat
    }

    /// 绑定数据库依赖（通过 Environment 注入）
    func attachDatabase(_ db: DatabaseManager) {
        self.db = db
    }

    /// 在主线程拍下分页参数快照，供后台线程使用
    func snapshotPaginationConfig(reading: ReadingSettings) -> PaginationConfig
    {
        PaginationConfig(
            screen: geoSize(),
            fontSize: CGFloat(reading.fontSize),
            lineSpacing: CGFloat(reading.lineSpacing)
        )
    }

    /// 设置屏幕尺寸（用于分页）
    func setScreenSize(_ size: CGSize) {
        self.screenSize = size
    }

    /// 计算阅读内容可用区域
    private func geoSize() -> CGSize {
        let bounds = screenSize
        return CGSize(width: bounds.width - 32, height: bounds.height - 140)
    }

    // MARK: - Data Loading
    /// 加载当前书籍信息（懒加载）
    func loadCurrentBook() {
        guard currentBook == nil else { return }
        guard let dbQueue = db?.dbQueue else { return }
        let bookId = self.currentChapter.bookid
        DispatchQueue.global(qos: .userInitiated).async {
            let t = PerfTimer("loadCurrentBook.dbRead", category: .performance)
            let loaded: Book? = try? dbQueue.read { db in
                let sql = """
                        SELECT b.id, b.title, a.name AS author, c.title AS category,
                               b.latest, b.wordcount, b.isfinished, b.updatedat
                        FROM book b
                        LEFT JOIN category c ON c.id = b.categoryid
                        LEFT JOIN author a ON a.id = b.authorid
                        WHERE b.id = ?
                    """
                if let row = try Row.fetchOne(
                    db,
                    sql: sql,
                    arguments: [bookId]
                ) {
                    let id: Int = row["id"]
                    let title: String = (row["title"] as String?) ?? ""
                    let author: String = (row["author"] as String?) ?? ""
                    let category: String = (row["category"] as String?) ?? ""
                    let latest: String = (row["latest"] as String?) ?? ""
                    let wordcount: Int = (row["wordcount"] as Int?) ?? 0
                    let isfinished: Int = (row["isfinished"] as Int?) ?? 0
                    let updatedat: Int = (row["updatedat"] as Int?) ?? 0
                    return Book(
                        id: id,
                        category: category,
                        title: title,
                        author: author,
                        latest: latest,
                        wordcount: wordcount,
                        isfinished: isfinished,
                        updatedat: updatedat
                    )
                } else {
                    return Book(
                        id: bookId,
                        category: "",
                        title: "",
                        author: "",
                        latest: "",
                        wordcount: 0,
                        isfinished: 0,
                        updatedat: 0
                    )
                }
            }
            t.end()
            DispatchQueue.main.async {
                self.currentBook = loaded
            }
        }
    }

    /// 加载目标章节的内容，并完成分页与缓存填充
    func loadContent(for chapter: Chapter, reading: ReadingSettings) {
        let config = snapshotPaginationConfig(reading: reading)

        // Cache hit fast path
        if let cachedContent = contentCache[chapter.id],
            let cachedParas = paragraphsCache[chapter.id]
        {
            Log.debug(
                "📚 loadContent cache hit chapterId=\(chapter.id)",
                category: .reader
            )
            self.content = cachedContent
            self.paragraphs = cachedParas
            if let cachedPages = pagesCache[chapter.id] {
                Log.debug(
                    "📚 use cached pages count=\(cachedPages.count)",
                    category: .reader
                )
                self.pages = cachedPages
                if let cachedParts = pagesPartsCache[chapter.id] {
                    self.pagesParts = cachedParts
                } else {
                    let parts = cachedPages.map {
                        $0.split(
                            separator: "\n",
                            omittingEmptySubsequences: false
                        ).map(String.init)
                    }
                    self.pagesParts = parts
                    self.pagesPartsCache[chapter.id] = parts
                }
                if showInitialSkeleton { showInitialSkeleton = false }
            } else {
                // Background paginate
                let txt = cachedContent.txt ?? ""
                Log.debug(
                    "📚 paginate cached content length=\(txt.count)",
                    category: .pagination
                )
                DispatchQueue.global(qos: .userInitiated).async {
                    let perfPg = PerfTimer(
                        "paginate.cached",
                        category: .performance
                    )
                    let newPages = Paginator.paginate(
                        text: txt,
                        fontSize: Double(config.fontSize),
                        screen: config.screen,
                        lineSpacing: Double(config.lineSpacing)
                    )
                    perfPg.end(
                        extra: "chapterId=\(chapter.id) pages=\(newPages.count)"
                    )
                    DispatchQueue.main.async {
                        self.pages = newPages
                        self.pagesCache[chapter.id] = newPages
                        self.touchCacheOrder(for: chapter.id)
                        let parts = newPages.map {
                            $0.split(
                                separator: "\n",
                                omittingEmptySubsequences: false
                            ).map(String.init)
                        }
                        self.pagesParts = parts
                        self.pagesPartsCache[chapter.id] = parts
                        if self.showInitialSkeleton && !newPages.isEmpty {
                            self.showInitialSkeleton = false
                        }
                    }
                }
            }
            return
        }

        guard let dbQueue = db?.dbQueue else { return }
        let chapterId = chapter.id
        let perfAll = PerfTimer("loadContent", category: .performance)
        DispatchQueue.global(qos: .userInitiated).async {
            let tDB = PerfTimer("loadContent.dbRead", category: .performance)
            let fetched: Content? = try? dbQueue.read { db in
                try Content
                    .filter(Column("chapterid") == chapter.id)
                    .fetchOne(db)
            }
            let txt = fetched?.txt ?? ""
            tDB.end(extra: "chapterId=\(chapter.id) textLen=\(txt.count)")
            Log.debug(
                "📚 loadContent from DB chapterId=\(chapter.id) textLen=\(txt.count)",
                category: .database
            )
            let tPara = PerfTimer(
                "loadContent.processParagraphs",
                category: .performance
            )
            let computedParas = Self.processParagraphs(txt)
            tPara.end(extra: "paras=\(computedParas.count)")
            let tPaginate = PerfTimer(
                "loadContent.paginate",
                category: .performance
            )
            let computedPages = Paginator.paginate(
                text: txt,
                fontSize: Double(config.fontSize),
                screen: config.screen,
                lineSpacing: Double(config.lineSpacing)
            )
            tPaginate.end(extra: "pages=\(computedPages.count)")
            DispatchQueue.main.async {
                Log.debug(
                    "📚 loadContent finish on main chapterId=\(chapterId) pages=\(computedPages.count)",
                    category: .reader
                )
                let tApply = PerfTimer(
                    "loadContent.applyMain",
                    category: .performance
                )
                self.content = fetched
                self.paragraphs = computedParas
                self.contentCache[chapterId] = fetched
                self.paragraphsCache[chapterId] = computedParas
                self.pages = computedPages
                self.pagesCache[chapterId] = computedPages
                let computedParts = computedPages.map {
                    $0.split(separator: "\n", omittingEmptySubsequences: false)
                        .map(String.init)
                }
                self.pagesParts = computedParts
                self.pagesPartsCache[chapterId] = computedParts
                self.touchCacheOrder(for: chapterId)
                if self.showInitialSkeleton && !computedPages.isEmpty {
                    self.showInitialSkeleton = false
                }
                self.updateAdjacentRefs()
                self.prefetchAroundCurrent(config: config)
                tApply.end()
                perfAll.end(extra: "chapterId=\(chapterId)")
            }
        }
    }

    /// 将整章文本切成段落，保留行首空格，去除行尾空白
    nonisolated private static func processParagraphs(_ text: String)
        -> [String]
    {
        var paragraphs: [String]
        if text.contains("\n\n") {
            paragraphs = text.components(separatedBy: "\n\n")
        } else if text.contains("\n") {
            paragraphs = text.components(separatedBy: "\n")
        } else {
            paragraphs = [text]
        }
        paragraphs =
            paragraphs
            .map { paragraph in
                paragraph.replacingOccurrences(
                    of: "\\s+$",
                    with: "",
                    options: .regularExpression
                )
            }
            .filter { !$0.isEmpty }
        return paragraphs
    }

    // MARK: - Chapters and Prefetch
    /// 获取相邻章节（上一章/下一章）
    func fetchAdjacentChapter(isNext: Bool) -> Chapter? {
        guard let dbQueue = db?.dbQueue else { return nil }
        return try? dbQueue.read { db in
            var request = Chapter.filter(
                Column("bookid") == currentChapter.bookid
            )
            if isNext {
                request =
                    request
                    .filter(Column("id") > currentChapter.id)
                    .order(Column("id"))
            } else {
                request =
                    request
                    .filter(Column("id") < currentChapter.id)
                    .order(Column("id").desc)
            }
            return try request.fetchOne(db)
        }
    }

    /// 批量获取相邻若干章节（用于预取）
    func fetchChapters(isNext: Bool, from chapter: Chapter, limit: Int)
        -> [Chapter]
    {
        guard let dbQueue = db?.dbQueue else { return [] }
        return
            (try? dbQueue.read { db -> [Chapter] in
                var request = Chapter.filter(Column("bookid") == chapter.bookid)
                if isNext {
                    request = request.filter(Column("id") > chapter.id).order(
                        Column("id")
                    ).limit(limit)
                } else {
                    request = request.filter(Column("id") < chapter.id).order(
                        Column("id").desc
                    ).limit(limit)
                }
                return try request.fetchAll(db)
            }) ?? []
    }

    /// 刷新相邻章节引用（供左右预览和切章使用）
    func updateAdjacentRefs() {
        prevChapterRef = fetchAdjacentChapter(isNext: false)
        nextChapterRef = fetchAdjacentChapter(isNext: true)
    }

    /// 确保目标章节已准备好（DB 读取 + 段落处理 + 分页 + 缓存），准备完成回调主线程
    func ensurePrepared(
        for chapter: Chapter,
        isCritical: Bool = false,
        config cfg: PaginationConfig,
        completion: @escaping () -> Void
    ) {
        let cid = chapter.id
        let hasCaches =
            (contentCache[cid] != nil) && (paragraphsCache[cid] != nil)
            && (pagesCache[cid] != nil)
        if hasCaches {
            Log.debug(
                "✅ ensurePrepared cache hit chapterId=\(cid)",
                category: .prefetch
            )
            DispatchQueue.main.async { completion() }
            return
        }
        guard let dbQueue = db?.dbQueue else {
            DispatchQueue.main.async { completion() }
            return
        }
        let perf = PerfTimer("ensurePrepared", category: .performance)
        DispatchQueue.global(qos: .userInitiated).async {
            if !isCritical {
                Self.prefetchSemaphore.wait()
            }
            defer {
                if !isCritical { Self.prefetchSemaphore.signal() }
            }
            let tDB = PerfTimer("ensurePrepared.dbRead", category: .performance)
            let fetched: Content? = try? dbQueue.read { db in
                try Content
                    .filter(Column("chapterid") == chapter.id)
                    .fetchOne(db)
            }
            let txt = fetched?.txt ?? ""
            tDB.end(extra: "chapterId=\(chapter.id) textLen=\(txt.count)")
            let tPara = PerfTimer(
                "ensurePrepared.processParagraphs",
                category: .performance
            )
            let computedParas = ReaderViewModel.processParagraphs(txt)
            tPara.end(extra: "paras=\(computedParas.count)")
            let tPaginate = PerfTimer(
                "ensurePrepared.paginate",
                category: .performance
            )
            let computedPages = Paginator.paginate(
                text: txt,
                fontSize: Double(cfg.fontSize),
                screen: cfg.screen,
                lineSpacing: Double(cfg.lineSpacing)
            )
            tPaginate.end(extra: "pages=\(computedPages.count)")
            DispatchQueue.main.async {
                self.contentCache[cid] = fetched
                self.paragraphsCache[cid] = computedParas
                self.pagesCache[cid] = computedPages
                let computedParts = computedPages.map {
                    $0.split(separator: "\n", omittingEmptySubsequences: false)
                        .map(String.init)
                }
                self.pagesPartsCache[cid] = computedParts
                self.touchCacheOrder(for: cid)
                Log.debug(
                    "✅ ensurePrepared ready chapterId=\(cid) pages=\(computedPages.count)",
                    category: .prefetch
                )
                completion()
                perf.end(extra: "chapterId=\(cid)")
            }
        }
    }

    /// 预取当前章节前后若干章节，提升切章秒开体验
    func prefetchAroundCurrent(config cfg: PaginationConfig) {
        let perf = PerfTimer("prefetchAroundCurrent", category: .performance)
        let prevs = fetchChapters(
            isNext: false,
            from: currentChapter,
            limit: prefetchRadius
        )
        let nexts = fetchChapters(
            isNext: true,
            from: currentChapter,
            limit: prefetchRadius
        )
        Log.debug(
            "🚚 prefetch candidates prev=\(prevs.count) next=\(nexts.count) radius=\(prefetchRadius)",
            category: .prefetch
        )
        for ch in prevs + nexts {
            if paragraphsCache[ch.id] == nil || pagesCache[ch.id] == nil
                || contentCache[ch.id] == nil
            {
                ensurePrepared(for: ch, isCritical: false, config: cfg) {}
            }
        }
        perf.end()
    }

    /// 根据 id 获取章节
    func fetchChapter(by id: Int) -> Chapter? {
        guard let dbQueue = db?.dbQueue else { return nil }
        return try? dbQueue.read { db in
            try Chapter.filter(Column("id") == id).fetchOne(db)
        }
    }

    // MARK: - Progress & Touch
    /// 保存阅读进度（百分比与页索引）
    func saveProgress(
        progressStore: ProgressStore,
        percent: Double = 0,
        pageIndex: Int? = nil
    ) {
        let progress = ReadingProgress(
            bookId: currentChapter.bookid,
            chapterId: currentChapter.id,
            percent: percent,
            pageIndex: pageIndex
        )
        progressStore.update(progress)
    }

    /// 首次进入时根据历史记录恢复进度（必要时切换章节）
    func restoreLastProgressIfNeeded(progressStore: ProgressStore) {
        guard needsInitialRestore else { return }
        guard
            let last = progressStore.lastProgress(
                forBook: currentChapter.bookid
            )
        else {
            Log.debug(
                "📖 restore: no last progress for bookId=\(currentChapter.bookid)"
            )
            needsInitialRestore = false
            return
        }
        Log.debug(
            "📖 restore: last chapterId=\(last.chapterId) percent=\(last.percent) pageIndex=\(String(describing: last.pageIndex)) currentChapterId=\(currentChapter.id)"
        )
        pendingRestorePercent = last.percent
        pendingRestorePageIndex = last.pageIndex
        if last.chapterId != currentChapter.id {
            if let target = fetchChapter(by: last.chapterId) {
                if target.bookid == currentChapter.bookid {
                    Log.debug("📖 restore: switch chapter to \(target.id)")
                    currentChapter = target
                } else {
                    Log.debug(
                        "📖 restore: skip mismatched book for chapterId=\(last.chapterId) currentBookId=\(currentChapter.bookid) targetBookId=\(target.bookid)"
                    )
                }
            }
        }
        needsInitialRestore = false
    }

    /// 触达 updatedat（带节流），标记书籍最近阅读时间
    func touchBookUpdatedAt(throttleSeconds: Int) {
        let now = Int(Date().timeIntervalSince1970)
        if throttleSeconds <= 0
            || now - lastBookUpdatedAtTouchUnixTime >= throttleSeconds
        {
            db?.touchBookUpdatedAt(bookId: currentChapter.bookid, at: now)
            lastBookUpdatedAtTouchUnixTime = now
        }
    }

    // MARK: - Favorites
    /// 添加收藏记录（携带定位与摘录）
    func addFavorite(excerpt: String, pageIndex: Int) {
        let percent =
            pages.count > 1 ? Double(pageIndex) / Double(pages.count - 1) : 0
        Log.debug(
            "⭐️ addFavorite bookId=\(currentChapter.bookid) chapterId=\(currentChapter.id) pageIndex=\(pageIndex) percent=\(percent) pages=\(pages.count)"
        )
        _ = db?.insertFavorite(
            bookId: currentChapter.bookid,
            chapterId: currentChapter.id,
            pageIndex: pageIndex,
            percent: percent,
            excerpt: excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// 读取阅读进度文案（可选百分比，基于 ProgressStore）
    func readingProgressText(
        for bookId: Int,
        progressStore: ProgressStore,
        includePercent: Bool = true
    ) -> String {
        guard let db else { return "" }
        return db.readingProgressText(
            forBookId: bookId,
            progressStore: progressStore,
            includePercent: includePercent
        )
    }

    // MARK: - LRU Cache
    /// 触碰缓存顺序并执行必要的淘汰
    private func touchCacheOrder(for chapterId: Int) {
        if let idx = cacheOrder.firstIndex(of: chapterId) {
            cacheOrder.remove(at: idx)
        }
        cacheOrder.append(chapterId)
        trimCachesIfNeeded()
    }

    /// 当缓存超限时按 LRU 淘汰
    private func trimCachesIfNeeded() {
        while cacheOrder.count > cacheCapacity {
            let evictId = cacheOrder.removeFirst()
            contentCache[evictId] = nil
            paragraphsCache[evictId] = nil
            pagesCache[evictId] = nil
            pagesPartsCache[evictId] = nil
            Log.debug("🧹 cache evict chapterId=\(evictId)", category: .prefetch)
        }
    }
}
