import GRDB
import SwiftUI

struct ReaderView: View {
    @State private var currentBook: Book?
    @State private var currentChapter: Chapter
    @State private var content: Content?
    @EnvironmentObject var progressStore: ProgressStore
    // 目录
    @State private var showCatalog: Bool = false
    // 阅读设置
    @State private var showSettings: Bool = false
    // 字体大小
    @State private var fontSize: CGFloat =
        UserDefaults.standard.double(forKey: "ReaderFontSize") != 0
        ? UserDefaults.standard.double(forKey: "ReaderFontSize") : 16
    // 行间距
    @State private var lineSpacing: CGFloat =
        UserDefaults.standard.double(forKey: "ReaderLineSpacing") != 0
        ? UserDefaults.standard.double(forKey: "ReaderLineSpacing") : 8
    // 段间距
    @State private var paragraphSpacing: CGFloat =
        UserDefaults.standard.double(forKey: "ReaderParagraphSpacing") != 0
        ? UserDefaults.standard.double(forKey: "ReaderParagraphSpacing") : 16
    // 背景色
    @State private var bgColor: Color =
        Color(
            hex: UserDefaults.standard.string(forKey: "ReaderBackgroundColor")
                ?? "#FFFFFF"
        ) ?? .white
    // 文字颜色
    @State private var textColor: Color =
        Color(
            hex: UserDefaults.standard.string(forKey: "ReaderTextColor")
                ?? "#000000"
        ) ?? .black

    // 拖拽偏移（用于左右滑动动画）
    @State private var dragOffset: CGFloat = 0

    // 段落渲染与缓存
    @State private var paragraphs: [String] = []
    @State private var paragraphsCache: [Int: [String]] = [:]  // chapterId -> paragraphs
    @State private var contentCache: [Int: Content] = [:]  // chapterId -> content
    // 分页渲染状态
    @State private var pages: [String] = []
    @State private var pagesCache: [Int: [String]] = [:]  // chapterId -> pages
    @State private var currentVisiblePageIndex: Int = 0
    @State private var showControls: Bool = false
    @State private var prevChapterRef: Chapter?
    @State private var nextChapterRef: Chapter?
    private let prefetchRadius: Int = 3
    // 首次进入时用于恢复进度
    @State private var needsInitialRestore: Bool = true
    @State private var pendingRestorePercent: Double? = nil
    @State private var pendingRestorePageIndex: Int? = nil

    init(chapter: Chapter) {
        _currentChapter = State(initialValue: chapter)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                leftPreviewView(geo: geo)
                contentScrollView(geo: geo)
                rightPreviewView(geo: geo)
            }
            .navigationTitle(currentChapter.title)
            .navigationBarTitleDisplayMode(.inline)
            .background(bgColor)
            .overlay(alignment: .bottom) { bottomControlsView(geo: geo) }
            .overlay(alignment: .top) {
                topControlsView(title: currentBook?.title ?? "")
            }
            .animation(.easeInOut(duration: 0.2), value: showControls)
            .sheet(isPresented: $showCatalog) {
                NavigationView {
                    if let book = currentBook {
                        ChapterListView(
                            book: book,
                            onSelect: { ch in
                                currentChapter = ch
                                loadContent(for: ch)
                                showCatalog = false
                            },
                            initialChapterId: currentChapter.id
                        )
                    } else {
                        Text("正在加载目录...")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                ReaderSettingsView(
                    fontSize: $fontSize,
                    lineSpacing: $lineSpacing,
                    paragraphSpacing: $paragraphSpacing,
                    bgColor: $bgColor,
                    textColor: $textColor
                )
            }
            .gesture(horizontalSwipeGesture(geo.size))
            .onTapGesture {
                withAnimation { showControls.toggle() }
            }
            .onAppear {
                dlog(
                    "📖 ReaderView.onAppear enter chapterId=\(currentChapter.id) bookId=\(currentChapter.bookid) pages=\(pages.count) needsInitialRestore=\(needsInitialRestore) pendingRestorePercent=\(String(describing: pendingRestorePercent)) pendingRestorePageIndex=\(String(describing: pendingRestorePageIndex))"
                )
                loadContent(for: currentChapter)
                loadSettings()
                loadCurrentBook()
                updateAdjacentRefs()
                prefetchAroundCurrent()
                if needsInitialRestore {
                    restoreLastProgressIfNeeded()
                }
            }
        }
    }

    // MARK: - Extracted Views
    @ViewBuilder
    private func leftPreviewView(geo: GeometryProxy) -> some View {
        if abs(dragOffset) > 0.1,
            let prev = prevChapterRef,
            let prevPages = pagesCache[prev.id]
        {
            chapterContentView(pagesArray: prevPages)
                .offset(x: -geo.size.width + dragOffset)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func rightPreviewView(geo: GeometryProxy) -> some View {
        if abs(dragOffset) > 0.1,
            let next = nextChapterRef,
            let nextPages = pagesCache[next.id]
        {
            chapterContentView(pagesArray: nextPages)
                .offset(x: geo.size.width + dragOffset)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func contentScrollView(geo: GeometryProxy) -> some View {
        // 中间：当前章节
        ScrollViewReader { proxy in
            ScrollView {
                if !pages.isEmpty {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(pages.indices, id: \.self) { idx in
                            pageView(pageIndex: idx)
                                .id(pageAnchorId(idx))
                        }
                    }
                } else {
                    loadingView
                }
            }
            .scrollIndicators(.hidden)
            .id(currentChapter.id)
            .offset(x: dragOffset)
            .onChange(of: pages) { oldPages, newPages in
                dlog(
                    "📖 onChange pages: old=\(oldPages.count) new=\(newPages.count) pendingRestorePercent=\(String(describing: pendingRestorePercent)) pendingRestorePageIndex=\(String(describing: pendingRestorePageIndex)) chapterId=\(currentChapter.id)"
                )
                guard !newPages.isEmpty else {
                    dlog("📖 onChange pages: pages empty, skip")
                    return
                }
                if let idx0 = pendingRestorePageIndex {
                    let idx = max(0, min(newPages.count - 1, idx0))
                    dlog(
                        "📖 restore via onChange (pageIndex) → scrollTo pageIndex=\(idx)"
                    )
                    DispatchQueue.main.async {
                        proxy.scrollTo(pageAnchorId(idx), anchor: .top)
                    }
                    pendingRestorePageIndex = nil
                    pendingRestorePercent = nil
                    currentVisiblePageIndex = idx
                    let computedPercent =
                        newPages.count > 1
                        ? Double(idx) / Double(newPages.count - 1) : 0
                    saveProgress(
                        percent: computedPercent,
                        pageIndex: idx
                    )
                } else if let percent = pendingRestorePercent {
                    let idx = restorePageIndex(
                        for: percent,
                        pagesCount: newPages.count
                    )
                    dlog(
                        "📖 restore via onChange (percent) → scrollTo pageIndex=\(idx) percent=\(percent)"
                    )
                    DispatchQueue.main.async {
                        proxy.scrollTo(pageAnchorId(idx), anchor: .top)
                    }
                    pendingRestorePercent = nil
                    currentVisiblePageIndex = idx
                    let computedPercent =
                        newPages.count > 1
                        ? Double(idx) / Double(newPages.count - 1) : 0
                    saveProgress(
                        percent: computedPercent,
                        pageIndex: idx
                    )
                } else {
                    dlog("📖 onChange pages: no pending restore, skip")
                }
            }
            .onAppear {
                dlog(
                    "📖 ScrollViewReader.onAppear pages=\(pages.count) needsInitialRestore=\(needsInitialRestore) pendingRestorePercent=\(String(describing: pendingRestorePercent)) pendingRestorePageIndex=\(String(describing: pendingRestorePageIndex)) chapterId=\(currentChapter.id)"
                )
                if needsInitialRestore {
                    restoreLastProgressIfNeeded()
                }
                if !pages.isEmpty {
                    if let idx0 = pendingRestorePageIndex {
                        let idx = max(0, min(pages.count - 1, idx0))
                        dlog(
                            "📖 immediate restore on appear (pageIndex) → scrollTo pageIndex=\(idx)"
                        )
                        DispatchQueue.main.async {
                            proxy.scrollTo(
                                pageAnchorId(idx),
                                anchor: .top
                            )
                        }
                        pendingRestorePageIndex = nil
                        pendingRestorePercent = nil
                        currentVisiblePageIndex = idx
                        let computedPercent =
                            pages.count > 1
                            ? Double(idx) / Double(pages.count - 1) : 0
                        saveProgress(
                            percent: computedPercent,
                            pageIndex: idx
                        )
                    } else if let percent = pendingRestorePercent {
                        let idx = restorePageIndex(
                            for: percent,
                            pagesCount: pages.count
                        )
                        dlog(
                            "📖 immediate restore on appear (percent) → scrollTo pageIndex=\(idx) percent=\(percent)"
                        )
                        DispatchQueue.main.async {
                            proxy.scrollTo(
                                pageAnchorId(idx),
                                anchor: .top
                            )
                        }
                        pendingRestorePercent = nil
                        currentVisiblePageIndex = idx
                        let computedPercent =
                            pages.count > 1
                            ? Double(idx) / Double(pages.count - 1) : 0
                        saveProgress(
                            percent: computedPercent,
                            pageIndex: idx
                        )
                    } else {
                        dlog(
                            "📖 ScrollViewReader.onAppear: no pending restore, skip"
                        )
                    }
                } else {
                    dlog(
                        "📖 ScrollViewReader.onAppear: pages empty, skip"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func bottomControlsView(geo: GeometryProxy) -> some View {
        if showControls {
            HStack {
                Button {
                    navigateToAdjacentChapter(
                        isNext: false,
                        containerWidth: geo.size.width
                    )
                } label: {
                    Label("上一章", systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                        .foregroundColor(textColor)
                }
                Spacer(minLength: 24)
                Button {
                    showCatalog = true
                } label: {
                    Image(systemName: "list.bullet")
                        .foregroundColor(textColor)
                }
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundColor(textColor)
                }
                Spacer(minLength: 24)
                Button {
                    navigateToAdjacentChapter(
                        isNext: true,
                        containerWidth: geo.size.width
                    )
                } label: {
                    HStack {
                        Text("下一章")
                        Image(systemName: "chevron.right")
                    }
                    .foregroundColor(textColor)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            .padding(.horizontal)
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private func topControlsView(title: String) -> some View {
        if showControls && !title.isEmpty {
            HStack {
                Spacer(minLength: 0)
                Text(title)
                    .font(.headline)
                    .foregroundColor(textColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            .padding(.horizontal)
            .padding(.top, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func loadContent(for chapter: Chapter) {
        // 命中缓存则直接返回，避免阻塞主线程
        if let cachedContent = contentCache[chapter.id],
            let cachedParas = paragraphsCache[chapter.id]
        {
            dlog("📚 loadContent cache hit chapterId=\(chapter.id)")
            content = cachedContent
            paragraphs = cachedParas
            if let cachedPages = pagesCache[chapter.id] {
                dlog("📚 use cached pages count=\(cachedPages.count)")
                pages = cachedPages
            } else {
                let txt = cachedContent.txt ?? ""
                dlog("📚 paginate cached content length=\(txt.count)")
                pages = paginate(
                    text: txt,
                    screen: geoSize(),
                    fontSize: fontSize,
                    lineSpacing: lineSpacing
                )
                pagesCache[chapter.id] = pages
            }
            return
        }

        guard let dbQueue = DatabaseManager.shared.dbQueue else { return }
        let chapterId = chapter.id

        DispatchQueue.global(qos: .userInitiated).async {
            let fetched: Content? = try? dbQueue.read { db in
                try Content
                    .filter(Column("chapterid") == chapter.id)
                    .fetchOne(db)
            }
            let txt = fetched?.txt ?? ""
            dlog(
                "📚 loadContent from DB chapterId=\(chapter.id) textLen=\(txt.count)"
            )
            let computedParas = processParagraphs(txt)
            let computedPages = paginate(
                text: txt,
                screen: geoSize(),
                fontSize: fontSize,
                lineSpacing: lineSpacing
            )

            DispatchQueue.main.async {
                dlog(
                    "📚 loadContent finish on main chapterId=\(chapterId) pages=\(computedPages.count)"
                )
                content = fetched
                paragraphs = computedParas
                contentCache[chapterId] = fetched
                paragraphsCache[chapterId] = computedParas
                pages = computedPages
                pagesCache[chapterId] = computedPages
                updateAdjacentRefs()
                prefetchAroundCurrent()
            }
        }
    }

    private func loadSettings() {
        // 重新加载所有设置
        let savedFontSize = UserDefaults.standard.double(
            forKey: "ReaderFontSize"
        )
        if savedFontSize != 0 {
            fontSize = savedFontSize
        }

        let savedLineSpacing = UserDefaults.standard.double(
            forKey: "ReaderLineSpacing"
        )
        if savedLineSpacing != 0 {
            lineSpacing = savedLineSpacing
        }

        let savedParagraphSpacing = UserDefaults.standard.double(
            forKey: "ReaderParagraphSpacing"
        )
        if savedParagraphSpacing != 0 {
            paragraphSpacing = savedParagraphSpacing
        }

        if let savedBgColor = UserDefaults.standard.string(
            forKey: "ReaderBackgroundColor"
        ),
            let color = Color(hex: savedBgColor)
        {
            bgColor = color
        }

        if let savedTextColor = UserDefaults.standard.string(
            forKey: "ReaderTextColor"
        ),
            let color = Color(hex: savedTextColor)
        {
            textColor = color
        }
    }

    private func processParagraphs(_ text: String) -> [String] {
        // 先尝试按双换行符分割，如果没有则按单换行符分割
        var paragraphs: [String]

        if text.contains("\n\n") {
            // 有双换行符，按双换行符分割
            paragraphs = text.components(separatedBy: "\n\n")
        } else if text.contains("\n") {
            // 没有双换行符，按单换行符分割
            paragraphs = text.components(separatedBy: "\n")
        } else {
            // 没有换行符，整个文本作为一个段落
            paragraphs = [text]
        }

        // 处理每个段落，保留开头的空格
        paragraphs =
            paragraphs
            .map { paragraph in
                // 只删除结尾的空白字符，保留开头的空格
                paragraph.replacingOccurrences(
                    of: "\\s+$",
                    with: "",
                    options: .regularExpression
                )
            }
            .filter { !$0.isEmpty }

        // print("分割出 \(paragraphs.count) 个段落")
        // print("文本长度: \(text.count), 包含换行符: \(text.contains("\n"))")
        return paragraphs
    }

    private func fetchAdjacentChapter(isNext: Bool) -> Chapter? {
        guard let dbQueue = DatabaseManager.shared.dbQueue else { return nil }
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

    private func navigateToAdjacentChapter(
        isNext: Bool,
        containerWidth: CGFloat
    ) {
        guard let target = fetchAdjacentChapter(isNext: isNext) else {
            withAnimation(.easeInOut) { dragOffset = 0 }
            return
        }

        let outOffset: CGFloat = isNext ? -containerWidth : containerWidth
        let animDuration: Double = 0.2

        // 先启动移出动画
        withAnimation(.easeInOut(duration: animDuration)) {
            dragOffset = outOffset
        }

        // 并行准备目标章节内容（优先命中缓存；未命中则后台加载）
        ensurePrepared(for: target) {
            // 在移出动画结束后切换章节，并无动画归零偏移，避免“再次滑入”的闪烁
            let deadline = DispatchTime.now() + animDuration
            DispatchQueue.main.asyncAfter(deadline: deadline) {
                currentChapter = target
                loadContent(for: target)
                updateAdjacentRefs()
                prefetchAroundCurrent()
                // 重置偏移（无动画），此时右侧/左侧预览已参与过滑动，不再二次滑入
                dragOffset = 0
            }
        }
    }

    // 确保某章内容已准备（命中缓存或后台填充缓存），完成后回调主线程
    private func ensurePrepared(
        for chapter: Chapter,
        completion: @escaping () -> Void
    ) {
        let cid = chapter.id
        let hasCaches =
            (contentCache[cid] != nil)
            && (paragraphsCache[cid] != nil)
            && (pagesCache[cid] != nil)
        if hasCaches {
            DispatchQueue.main.async { completion() }
            return
        }
        guard let dbQueue = DatabaseManager.shared.dbQueue else {
            DispatchQueue.main.async { completion() }
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let fetched: Content? = try? dbQueue.read { db in
                try Content
                    .filter(Column("chapterid") == chapter.id)
                    .fetchOne(db)
            }
            let txt = fetched?.txt ?? ""
            let computedParas = processParagraphs(txt)
            let computedPages = paginate(
                text: txt,
                screen: geoSize(),
                fontSize: fontSize,
                lineSpacing: lineSpacing
            )
            DispatchQueue.main.async {
                contentCache[cid] = fetched
                paragraphsCache[cid] = computedParas
                pagesCache[cid] = computedPages
                completion()
            }
        }
    }

    // 预取前后多章，提升左右滑动时的秒开体验
    private func prefetchAroundCurrent() {
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
        for ch in prevs + nexts {
            if paragraphsCache[ch.id] == nil || pagesCache[ch.id] == nil
                || contentCache[ch.id] == nil
            {
                ensurePrepared(for: ch) {}
            }
        }
    }

    private func fetchChapters(isNext: Bool, from chapter: Chapter, limit: Int)
        -> [Chapter]
    {
        guard let dbQueue = DatabaseManager.shared.dbQueue else { return [] }
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

    private func updateAdjacentRefs() {
        prevChapterRef = fetchAdjacentChapter(isNext: false)
        nextChapterRef = fetchAdjacentChapter(isNext: true)
    }

    // MARK: - Pagination helpers
    private func geoSize() -> CGSize {
        // 使用屏幕尺寸近似分页，避免在 body 外部拿 geo.size
        let bounds = UIScreen.main.bounds
        // 减去大致的安全区/导航区和内边距
        return CGSize(width: bounds.width - 32, height: bounds.height - 140)
    }

    private func paginate(
        text: String,
        screen: CGSize,
        fontSize: CGFloat,
        lineSpacing: CGFloat
    ) -> [String] {
        Paginator.paginate(
            text: text,
            fontSize: Double(fontSize),
            screen: screen,
            lineSpacing: Double(lineSpacing)
        )
    }

    private func loadCurrentBook() {
        guard currentBook == nil else { return }
        guard let dbQueue = DatabaseManager.shared.dbQueue else { return }
        currentBook = try? dbQueue.read { db in
            let sql = """
                    SELECT b.id, b.title, a.name AS author, c.title AS category,
                           b.latest AS latest, b.wordcount AS wordcount, b.isfinished AS isfinished
                    FROM book b
                    LEFT JOIN category c ON c.id = b.categoryid
                    LEFT JOIN book_author a ON a.id = b.authorid
                    WHERE b.id = ?
                """
            if let row = try Row.fetchOne(
                db,
                sql: sql,
                arguments: [currentChapter.bookid]
            ) {
                let id: Int = row["id"]
                let title: String = (row["title"] as String?) ?? ""
                let author: String = (row["author"] as String?) ?? ""
                let category: String = (row["category"] as String?) ?? ""
                let latest: String = (row["latest"] as String?) ?? ""
                let wordcount: Int = (row["wordcount"] as Int?) ?? 0
                let isfinished: Int = (row["isfinished"] as Int?) ?? 0

                return Book(
                    id: id,
                    category: category,
                    title: title,
                    author: author,
                    latest: latest,
                    wordcount: wordcount,
                    isfinished: isfinished
                )
            } else {
                return Book(
                    id: currentChapter.bookid,
                    category: "",
                    title: "",
                    author: "",
                    latest: "",
                    wordcount: 0,
                    isfinished: 0
                )
            }
        }
    }

    private func saveProgress(percent: Double = 0, pageIndex: Int? = nil) {
        let progress = ReadingProgress(
            bookId: currentChapter.bookid,
            chapterId: currentChapter.id,
            percent: percent,
            pageIndex: pageIndex
        )
        progressStore.update(progress)
    }

    // 根据记录恢复进度：必要时切换章节，并在分页后滚动到对应百分比
    private func restoreLastProgressIfNeeded() {
        guard needsInitialRestore else { return }
        guard
            let last = progressStore.lastProgress(
                forBook: currentChapter.bookid
            )
        else {
            dlog(
                "📖 restore: no last progress for bookId=\(currentChapter.bookid)"
            )
            needsInitialRestore = false
            return
        }

        dlog(
            "📖 restore: last chapterId=\(last.chapterId) percent=\(last.percent) pageIndex=\(String(describing: last.pageIndex)) currentChapterId=\(currentChapter.id)"
        )
        pendingRestorePercent = last.percent
        pendingRestorePageIndex = last.pageIndex

        if last.chapterId != currentChapter.id {
            if let target = fetchChapter(by: last.chapterId) {
                if target.bookid == currentChapter.bookid {
                    dlog("📖 restore: switch chapter to \(target.id)")
                    currentChapter = target
                    loadContent(for: target)
                    updateAdjacentRefs()
                    prefetchAroundCurrent()
                } else {
                    dlog(
                        "📖 restore: skip mismatched book for chapterId=\(last.chapterId) currentBookId=\(currentChapter.bookid) targetBookId=\(target.bookid)"
                    )
                }
            }
        }

        needsInitialRestore = false
    }

    private func fetchChapter(by id: Int) -> Chapter? {
        guard let dbQueue = DatabaseManager.shared.dbQueue else { return nil }
        return try? dbQueue.read { db in
            try Chapter.fetchOne(db, key: id)
        }
    }

    // MARK: - View helpers
    private var loadingView: some View {
        Text("加载中...")
            .font(.system(size: fontSize))
            .foregroundColor(textColor)
            .padding()
    }

    @ViewBuilder
    private func pageView(pageIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(pages[pageIndex])
                .font(.system(size: fontSize))
                .foregroundColor(textColor)
                .lineSpacing(lineSpacing)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .onAppear { onPageAppear(pageIndex) }
    }

    private func paragraphsInPage(_ index: Int) -> [String] {
        if index < 0 || index >= pages.count { return [] }
        return pages[index]
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }

    private func onPageAppear(_ pageIndex: Int) {
        currentVisiblePageIndex = pageIndex
        let percent =
            pages.count > 1
            ? Double(pageIndex) / Double(pages.count - 1)
            : 0
        dlog(
            "📝 onPageAppear pageIndex=\(pageIndex) percent=\(percent) pages=\(pages.count) chapterId=\(currentChapter.id)"
        )
        saveProgress(percent: percent, pageIndex: pageIndex)
    }

    private func pageAnchorId(_ index: Int) -> String { "page-\(index)" }

    private func restorePageIndex(for percent: Double, pagesCount: Int) -> Int {
        let clamped = max(0, min(1, percent))
        guard pagesCount > 1 else { return 0 }
        return Int(round(clamped * Double(pagesCount - 1)))
    }

    private func horizontalSwipeGesture(_ size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if abs(value.translation.width) > abs(value.translation.height)
                {
                    let limit = size.width
                    let proposed = value.translation.width
                    dragOffset = max(-limit, min(limit, proposed))
                }
            }
            .onEnded { value in
                let threshold = size.width * 0.25
                if abs(value.translation.width) <= abs(value.translation.height)
                {
                    withAnimation(.easeInOut) { dragOffset = 0 }
                    return
                }
                if value.translation.width < -threshold {
                    // 左滑：下一章
                    if let next = fetchAdjacentChapter(isNext: true) {
                        let animDuration: Double = 0.2
                        withAnimation(.easeInOut(duration: animDuration)) {
                            dragOffset = -size.width
                        }
                        ensurePrepared(for: next) {
                            let deadline = DispatchTime.now() + animDuration
                            DispatchQueue.main.asyncAfter(deadline: deadline) {
                                currentChapter = next
                                loadContent(for: next)
                                updateAdjacentRefs()
                                prefetchAroundCurrent()
                                // 无动画复位，避免二次滑入闪烁
                                dragOffset = 0
                            }
                        }
                    } else {
                        withAnimation(.easeInOut) { dragOffset = 0 }
                    }
                } else if value.translation.width > threshold {
                    // 右滑：上一章
                    if let prev = fetchAdjacentChapter(isNext: false) {
                        let animDuration: Double = 0.2
                        withAnimation(.easeInOut(duration: animDuration)) {
                            dragOffset = size.width
                        }
                        ensurePrepared(for: prev) {
                            let deadline = DispatchTime.now() + animDuration
                            DispatchQueue.main.asyncAfter(deadline: deadline) {
                                currentChapter = prev
                                loadContent(for: prev)
                                updateAdjacentRefs()
                                prefetchAroundCurrent()
                                // 无动画复位，避免二次滑入闪烁
                                dragOffset = 0
                            }
                        }
                    } else {
                        withAnimation(.easeInOut) { dragOffset = 0 }
                    }
                } else {
                    withAnimation(.easeInOut) { dragOffset = 0 }
                }
            }
    }

    private func dlog(_ message: String) {
        if UserDefaults.standard.bool(forKey: "ReaderDebugLoggingEnabled") {
            print(message)
        }
    }

    // 渲染某一章的内容（用于左右两侧的预览/滑入）
    @ViewBuilder
    private func chapterContentView(pagesArray: [String]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(pagesArray.indices, id: \.self) { idx in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(pagesArray[idx])
                            .font(.system(size: fontSize))
                            .foregroundColor(textColor)
                            .lineSpacing(lineSpacing)
                            .multilineTextAlignment(.leading)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Color Extension
extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(
            in: CharacterSet.alphanumerics.inverted
        )
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a: UInt64
        let r: UInt64
        let g: UInt64
        let b: UInt64
        switch hex.count {
        case 3:  // RGB (12-bit)
            (a, r, g, b) = (
                255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17
            )
        case 6:  // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  // ARGB (32-bit)
            (a, r, g, b) = (
                int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF
            )
        default:
            return nil
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
