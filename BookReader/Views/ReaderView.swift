import GRDB
import SwiftUI

struct ReaderView: View {
    @EnvironmentObject private var db: DatabaseManager
    @State private var currentBook: Book?
    @State private var currentChapter: Chapter
    @State private var content: Content?
    @EnvironmentObject var progressStore: ProgressStore
    @EnvironmentObject private var reading: ReadingSettings

    @Environment(\.dismiss) private var dismiss

    // 目录
    @State private var showCatalog: Bool = false
    // 阅读设置
    @State private var showSettings: Bool = false

    // 拖拽偏移（用于左右滑动动画）
    @State private var dragOffset: CGFloat = 0
    // 是否处于左右滑动中（用于临时隐藏滚动条）
    @State private var isHorizontalSwiping: Bool = false

    // 章节标题额外上下间距
    @State private var chapterTitleTopPadding: CGFloat = 12
    @State private var chapterTitleBottomPadding: CGFloat = 10

    // 段落渲染与缓存
    @State private var screenSize: CGSize = .zero
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
    @State private var prefetchRadius: Int = 1
    private static let prefetchSemaphore: DispatchSemaphore = DispatchSemaphore(
        value: 2
    )
    // 首次进入时用于恢复进度
    @State private var needsInitialRestore: Bool = true
    @State private var pendingRestorePercent: Double? = nil
    @State private var pendingRestorePageIndex: Int? = nil
    @State private var pendingRestoreChapterId: Int? = nil
    // 触达书籍更新时间节流
    @State private var lastBookUpdatedAtTouchUnixTime: Int = 0

    // 收藏
    @State private var showFavorites: Bool = false
    @State private var showAddFavoriteDialog: Bool = false
    @State private var draftExcerpt: String = ""
    @State private var draftFavoritePageIndex: Int? = nil
    @State private var showBookInfo: Bool = false

    // 边界提示（第一章/最后一章）
    @State private var showEdgeAlert: Bool = false
    @State private var edgeAlertMessage: String = ""

    // 仅用于从书籍列表首次进入时显示骨架占位，章节切换不使用
    @State private var showInitialSkeleton: Bool = false

    @Namespace private var controlsNamespace

    init(chapter: Chapter, isInitialFromBookList: Bool = false) {
        _currentChapter = State(initialValue: chapter)
        _showInitialSkeleton = State(initialValue: isInitialFromBookList)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                leftPreviewView(geo: geo)
                contentScrollView(geo: geo)
                rightPreviewView(geo: geo)
            }
            .toolbar(.hidden, for: .navigationBar)
            .background(reading.backgroundColor)
            .overlay(alignment: .bottom) { bottomControlsView(geo: geo) }
            .overlay(alignment: .top) { topControlsView() }
            .overlay {
                if showAddFavoriteDialog {
                    TextFieldDialog(
                        title: String(localized: "favorite.add_to_favorites"),
                        placeholder: String(
                            localized: "favorite.add_to_favorites_placeholder"
                        ),
                        text: $draftExcerpt,
                        onCancel: {
                            showAddFavoriteDialog = false
                        },
                        onSave: {
                            let pageIdx =
                                draftFavoritePageIndex
                                ?? currentVisiblePageIndex
                            addFavorite(
                                excerpt: draftExcerpt,
                                pageIndex: pageIdx
                            )
                            showAddFavoriteDialog = false
                        }
                    )
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showControls)
            .sheet(isPresented: $showCatalog) {
                NavigationStack {
                    if let book = currentBook {
                        ChapterListView(
                            book: book,
                            onSelect: { ch in
                                currentChapter = ch
                                loadContent(for: ch)
                                // 从目录跳转时立即触达
                                touchCurrentBookUpdatedAt(throttleSeconds: 0)
                                showCatalog = false
                            },
                            initialChapterId: currentChapter.id
                        )
                    } else {
                        Text(String(localized: "reading.book_index_loading"))
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                ReaderSettingsView()
            }
            .sheet(isPresented: $showFavorites) {
                FavoritesView(bookId: currentChapter.bookid) { fav in
                    jump(to: fav)
                    showFavorites = false
                }
            }
            .sheet(isPresented: $showBookInfo) {
                if let book = currentBook {
                    BookInfoView(
                        book: book,
                        progressText: progressText(for: book)
                    )
                } else {
                    ProgressView()
                        .padding()
                }
            }
            .alert(isPresented: $showEdgeAlert) {
                Alert(
                    title: Text(edgeAlertMessage),
                    dismissButton: .default(Text(String(localized: "btn.ok")))
                )
            }
            .contentShape(Rectangle())
            .highPriorityGesture(spatialDoubleTapGesture(geo: geo))
            .simultaneousGesture(horizontalSwipeGesture(geo.size))
            .onTapGesture {
                withAnimation { showControls.toggle() }
            }
            .onAppear {
                let perf = PerfTimer(
                    "ReaderView.onAppear",
                    category: .performance
                )
                Log.debug(
                    "📖 ReaderView.onAppear enter chapterId=\(currentChapter.id) bookId=\(currentChapter.bookid) pages=\(pages.count) needsInitialRestore=\(needsInitialRestore) pendingRestorePercent=\(String(describing: pendingRestorePercent)) pendingRestorePageIndex=\(String(describing: pendingRestorePageIndex))",
                    category: .reader
                )

                screenSize = geo.size

                loadContent(for: currentChapter)
                loadCurrentBook()
                updateAdjacentRefs()
                if needsInitialRestore {
                    restoreLastProgressIfNeeded()
                }
                // 进入阅读页即触达一次（节流保护）
                touchCurrentBookUpdatedAt(throttleSeconds: 30)

                // 首帧后小延时扩大预取半径并进行二次预取（避免首屏压力）
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    prefetchRadius = 3
                    prefetchAroundCurrent()
                }

                // 监听取消模态视图的通知
                NotificationCenter.default.addObserver(
                    forName: .dismissAllModals,
                    object: nil,
                    queue: .main
                ) { _ in
                    showCatalog = false
                    showSettings = false
                    showFavorites = false
                    showAddFavoriteDialog = false
                    showBookInfo = false
                    showControls = false
                }
                perf.end()
            }
            .onChange(of: geo.size) { _, newSize in
                screenSize = newSize
            }
            .onDisappear {
                // 移除通知监听器
                NotificationCenter.default.removeObserver(self)
            }
        }
    }

    // 列表展示的阅读进度文案（含百分比）
    private func progressText(for book: Book) -> String {
        db.readingProgressText(
            forBookId: book.id,
            progressStore: progressStore,
            includePercent: true
        )
    }

    // MARK: - Extracted Views
    @ViewBuilder
    private func leftPreviewView(geo: GeometryProxy) -> some View {
        if abs(dragOffset) > 0.1,
            let prev = prevChapterRef,
            let prevPages = pagesCache[prev.id]
        {
            chapterContentView(pagesArray: prevPages, title: prev.title)
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
            chapterContentView(pagesArray: nextPages, title: next.title)
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
                    if showInitialSkeleton {
                        initialSkeletonView
                    } else {
                        loadingView
                    }
                }
            }
            .background(reading.backgroundColor)
            .scrollIndicators(isHorizontalSwiping ? .hidden : .visible)
            .id(currentChapter.id)
            .offset(x: dragOffset)
            .onChange(of: pages) { oldPages, newPages in
                Log.debug(
                    "📖 onChange pages: old=\(oldPages.count) new=\(newPages.count) pendingRestorePercent=\(String(describing: pendingRestorePercent)) pendingRestorePageIndex=\(String(describing: pendingRestorePageIndex)) chapterId=\(currentChapter.id)"
                )
                guard !newPages.isEmpty else {
                    Log.debug("📖 onChange pages: pages empty, skip")
                    return
                }
                if showInitialSkeleton { showInitialSkeleton = false }
                // 仅当目标章节就是当前章节时才应用恢复
                let shouldApplyRestore =
                    (pendingRestoreChapterId == nil)
                    || (pendingRestoreChapterId == currentChapter.id)
                guard shouldApplyRestore else {
                    Log.debug(
                        "📖 onChange pages: pending for chapterId=\(String(describing: pendingRestoreChapterId)), current=\(currentChapter.id), skip"
                    )
                    return
                }
                if let idx0 = pendingRestorePageIndex {
                    let idx = max(0, min(newPages.count - 1, idx0))
                    Log.debug(
                        "📖 restore via onChange (pageIndex) → scrollTo pageIndex=\(idx)"
                    )
                    scrollToPage(idx, using: proxy, animated: true)
                    pendingRestorePageIndex = nil
                    pendingRestorePercent = nil
                    pendingRestoreChapterId = nil
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
                    Log.debug(
                        "📖 restore via onChange (percent) → scrollTo pageIndex=\(idx) percent=\(percent)"
                    )
                    scrollToPage(idx, using: proxy, animated: true)
                    pendingRestorePercent = nil
                    pendingRestoreChapterId = nil
                    currentVisiblePageIndex = idx
                    let computedPercent =
                        newPages.count > 1
                        ? Double(idx) / Double(newPages.count - 1) : 0
                    saveProgress(
                        percent: computedPercent,
                        pageIndex: idx
                    )
                } else {
                    Log.debug(
                        "📖 onChange pages: no pending restore, skip"
                    )
                }
            }
            // 收藏跳转：同章节情况下也能立即滚动
            .onChange(of: pendingRestorePageIndex) { oldValue, newValue in
                guard let idx0 = newValue, !pages.isEmpty else { return }
                let shouldApplyRestore =
                    (pendingRestoreChapterId == nil)
                    || (pendingRestoreChapterId == currentChapter.id)
                guard shouldApplyRestore else {
                    Log.debug(
                        "📖 onChange pendingRestorePageIndex: pending for chapterId=\(String(describing: pendingRestoreChapterId)), current=\(currentChapter.id), skip"
                    )
                    return
                }
                let idx = max(0, min(pages.count - 1, idx0))
                Log.debug(
                    "📖 onChange pendingRestorePageIndex → scrollTo pageIndex=\(idx)"
                )
                scrollToPage(idx, using: proxy, animated: true)
                pendingRestorePageIndex = nil
                pendingRestorePercent = nil
                pendingRestoreChapterId = nil
                currentVisiblePageIndex = idx
                let computedPercent =
                    pages.count > 1 ? Double(idx) / Double(pages.count - 1) : 0
                saveProgress(percent: computedPercent, pageIndex: idx)
            }
            .onChange(of: pendingRestorePercent) { oldValue, newValue in
                guard let percent = newValue, !pages.isEmpty else { return }
                let shouldApplyRestore =
                    (pendingRestoreChapterId == nil)
                    || (pendingRestoreChapterId == currentChapter.id)
                guard shouldApplyRestore else {
                    Log.debug(
                        "📖 onChange pendingRestorePercent: pending for chapterId=\(String(describing: pendingRestoreChapterId)), current=\(currentChapter.id), skip"
                    )
                    return
                }
                let idx = restorePageIndex(
                    for: percent,
                    pagesCount: pages.count
                )
                Log.debug(
                    "📖 onChange pendingRestorePercent → scrollTo pageIndex=\(idx) percent=\(percent)"
                )
                scrollToPage(idx, using: proxy, animated: true)
                pendingRestorePercent = nil
                pendingRestoreChapterId = nil
                currentVisiblePageIndex = idx
                let computedPercent =
                    pages.count > 1 ? Double(idx) / Double(pages.count - 1) : 0
                saveProgress(percent: computedPercent, pageIndex: idx)
            }
            // 章节切换完成的兜底：若目标章与当前章一致且 pages 已就绪，则立即恢复
            .onChange(of: currentChapter.id) { oldId, newId in
                Log.debug(
                    "📖 onChange currentChapterId old=\(oldId) new=\(newId) pendingChapter=\(String(describing: pendingRestoreChapterId)) pendingPageIndex=\(String(describing: pendingRestorePageIndex)) pendingPercent=\(String(describing: pendingRestorePercent)) pages=\(pages.count)"
                )
                guard let targetChapterId = pendingRestoreChapterId,
                    targetChapterId == newId
                else { return }
                if let idx0 = pendingRestorePageIndex, !pages.isEmpty {
                    let idx = max(0, min(pages.count - 1, idx0))
                    Log.debug(
                        "📖 restore via onChange(currentChapterId) (pageIndex) → scrollTo pageIndex=\(idx)"
                    )
                    scrollToPage(idx, using: proxy, animated: true)
                    pendingRestorePageIndex = nil
                    pendingRestorePercent = nil
                    pendingRestoreChapterId = nil
                    currentVisiblePageIndex = idx
                    let computedPercent =
                        pages.count > 1
                        ? Double(idx) / Double(pages.count - 1) : 0
                    saveProgress(percent: computedPercent, pageIndex: idx)
                } else if let percent = pendingRestorePercent, !pages.isEmpty {
                    let idx = restorePageIndex(
                        for: percent,
                        pagesCount: pages.count
                    )
                    Log.debug(
                        "📖 restore via onChange(currentChapterId) (percent) → scrollTo pageIndex=\(idx) percent=\(percent)"
                    )
                    scrollToPage(idx, using: proxy, animated: true)
                    pendingRestorePercent = nil
                    pendingRestoreChapterId = nil
                    currentVisiblePageIndex = idx
                    let computedPercent =
                        pages.count > 1
                        ? Double(idx) / Double(pages.count - 1) : 0
                    saveProgress(percent: computedPercent, pageIndex: idx)
                } else {
                    // pages 还未就绪，等待 onChange(pages) 处理
                }
            }
            .onAppear {
                Log.debug(
                    "📖 ScrollViewReader.onAppear pages=\(pages.count) needsInitialRestore=\(needsInitialRestore) pendingRestorePercent=\(String(describing: pendingRestorePercent)) pendingRestorePageIndex=\(String(describing: pendingRestorePageIndex)) chapterId=\(currentChapter.id)"
                )
                if needsInitialRestore {
                    restoreLastProgressIfNeeded()
                }
                if !pages.isEmpty {
                    if let idx0 = pendingRestorePageIndex {
                        let idx = max(0, min(pages.count - 1, idx0))
                        Log.debug(
                            "📖 immediate restore on appear (pageIndex) → scrollTo pageIndex=\(idx)"
                        )
                        scrollToPage(idx, using: proxy, animated: false)
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
                        Log.debug(
                            "📖 immediate restore on appear (percent) → scrollTo pageIndex=\(idx) percent=\(percent)"
                        )
                        scrollToPage(idx, using: proxy, animated: false)
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
                        Log.debug(
                            "📖 ScrollViewReader.onAppear: no pending restore, skip"
                        )
                    }
                } else {
                    Log.debug(
                        "📖 ScrollViewReader.onAppear: pages empty, skip"
                    )
                }
            }
        }
    }

    @ViewBuilder
    func circularButton(
        systemName: String,
        title: String,
        applyGlass: Bool = true,
        namespace: Namespace.ID,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(reading.textColor)
                .actionIcon()
        }
        .glassCircleButton(
            foreground: reading.textColor,
            background: reading.backgroundColor,
            applyGlass: applyGlass
        )
        .glassEffectID(title, in: namespace)
        .accessibilityLabel(
            NSLocalizedString(title, comment: "")
        )
    }

    @ViewBuilder
    private func bottomControlsView(geo: GeometryProxy) -> some View {
        if showControls {
            HStack(spacing: 0) {
                // Left: Previous chapter
                circularButton(
                    systemName: "arrow.backward",
                    title: "btn.prev",
                    namespace: controlsNamespace
                ) {
                    navigateToAdjacentChapter(
                        isNext: false,
                        containerWidth: geo.size.width
                    )
                }

                Spacer(minLength: 16)

                // Center: Toolbar with three actions
                HStack(spacing: 16) {
                    circularButton(
                        systemName: "list.bullet",
                        title: "btn.index",
                        applyGlass: false,
                        namespace: controlsNamespace
                    ) {
                        showCatalog = true
                    }

                    circularButton(
                        systemName: "bookmark",
                        title: "btn.favorite",
                        applyGlass: false,
                        namespace: controlsNamespace
                    ) {
                        showFavorites = true
                    }

                    circularButton(
                        systemName: "gear",
                        title: "btn.setting",
                        applyGlass: false,
                        namespace: controlsNamespace
                    ) {
                        showSettings = true
                    }
                }
                .padding(.horizontal)
                .background(reading.backgroundColor.opacity(0.5))
                .glassEffect(.clear.interactive())
                .cornerRadius(22)

                Spacer(minLength: 16)

                // Right: Next chapter
                circularButton(
                    systemName: "arrow.forward",
                    title: "btn.next",
                    namespace: controlsNamespace
                ) {
                    navigateToAdjacentChapter(
                        isNext: true,
                        containerWidth: geo.size.width
                    )
                }
            }
            .padding(.horizontal)
            .padding(.top, 10)
            .padding(.bottom, 10)
            .background(.clear)
            .frame(maxWidth: .infinity)
            .padding(.horizontal)
            .padding(.bottom, 5)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private func topControlsView() -> some View {

        if showControls {
            HStack {
                circularButton(
                    systemName: "chevron.left",
                    title: "btn.back",
                    namespace: controlsNamespace
                ) {
                    dismiss()
                }

                Text(currentChapter.title)
                    .font(.headline)
                    .foregroundColor(reading.textColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 11)
                    .background(reading.backgroundColor.opacity(0.8))
                    .cornerRadius(22)

                circularButton(
                    systemName: "book",
                    title: "book_info.title",
                    namespace: controlsNamespace
                ) {
                    showBookInfo = true
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func loadContent(for chapter: Chapter) {
        // 命中缓存则直接返回，避免阻塞主线程
        if let cachedContent = contentCache[chapter.id],
            let cachedParas = paragraphsCache[chapter.id]
        {
            Log.debug(
                "📚 loadContent cache hit chapterId=\(chapter.id)",
                category: .reader
            )
            content = cachedContent
            paragraphs = cachedParas
            if let cachedPages = pagesCache[chapter.id] {
                Log.debug(
                    "📚 use cached pages count=\(cachedPages.count)",
                    category: .reader
                )
                pages = cachedPages
                if showInitialSkeleton { showInitialSkeleton = false }
            } else {
                let txt = cachedContent.txt ?? ""
                Log.debug(
                    "📚 paginate cached content length=\(txt.count)",
                    category: .pagination
                )
                let perfPg = PerfTimer(
                    "paginate.cached",
                    category: .performance
                )
                let newPages = paginate(
                    text: txt,
                    screen: geoSize(),
                    fontSize: CGFloat(reading.fontSize),
                    lineSpacing: CGFloat(reading.lineSpacing)
                )
                pages = newPages
                pagesCache[chapter.id] = newPages
                if showInitialSkeleton && !newPages.isEmpty {
                    showInitialSkeleton = false
                }
                perfPg.end(
                    extra: "chapterId=\(chapter.id) pages=\(newPages.count)"
                )
            }
            return
        }

        guard let dbQueue = DatabaseManager.shared.dbQueue else { return }
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
            let computedParas = processParagraphs(txt)
            tPara.end(extra: "paras=\(computedParas.count)")
            let tPaginate = PerfTimer(
                "loadContent.paginate",
                category: .performance
            )
            let computedPages = paginate(
                text: txt,
                screen: geoSize(),
                fontSize: CGFloat(reading.fontSize),
                lineSpacing: CGFloat(reading.lineSpacing)
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
                content = fetched
                paragraphs = computedParas
                contentCache[chapterId] = fetched
                paragraphsCache[chapterId] = computedParas
                pages = computedPages
                pagesCache[chapterId] = computedPages
                if showInitialSkeleton && !computedPages.isEmpty {
                    showInitialSkeleton = false
                }
                updateAdjacentRefs()
                prefetchAroundCurrent()
                tApply.end()
                perfAll.end(extra: "chapterId=\(chapterId)")
            }
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

        // Log.debug("分割出 \(paragraphs.count) 个段落")
        // Log.debug("文本长度: \(text.count), 包含换行符: \(text.contains("\n"))")
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
            edgeAlertMessage =
                isNext
                ? String(localized: "reading.is_last_chapter")
                : String(localized: "reading.is_first_chapter")
            showEdgeAlert = true
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
        ensurePrepared(for: target, isCritical: true) {
            // 在移出动画结束后切换章节，并无动画归零偏移，避免“再次滑入”的闪烁
            let deadline = DispatchTime.now() + animDuration
            DispatchQueue.main.asyncAfter(deadline: deadline) {
                currentChapter = target
                loadContent(for: target)
                updateAdjacentRefs()
                prefetchAroundCurrent()
                // 重置偏移（无动画），此时右侧/左侧预览已参与过滑动，不再二次滑入
                dragOffset = 0
                // 按钮切章也触达
                touchCurrentBookUpdatedAt(throttleSeconds: 0)
            }
        }
    }

    // 确保某章内容已准备（命中缓存或后台填充缓存），完成后回调主线程
    private func ensurePrepared(
        for chapter: Chapter,
        isCritical: Bool = false,
        completion: @escaping () -> Void
    ) {
        let cid = chapter.id
        let hasCaches =
            (contentCache[cid] != nil)
            && (paragraphsCache[cid] != nil)
            && (pagesCache[cid] != nil)
        if hasCaches {
            Log.debug(
                "✅ ensurePrepared cache hit chapterId=\(cid)",
                category: .prefetch
            )
            DispatchQueue.main.async { completion() }
            return
        }
        guard let dbQueue = DatabaseManager.shared.dbQueue else {
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
            let computedParas = processParagraphs(txt)
            tPara.end(extra: "paras=\(computedParas.count)")
            let tPaginate = PerfTimer(
                "ensurePrepared.paginate",
                category: .performance
            )
            let computedPages = paginate(
                text: txt,
                screen: geoSize(),
                fontSize: CGFloat(reading.fontSize),
                lineSpacing: CGFloat(reading.lineSpacing)
            )
            tPaginate.end(extra: "pages=\(computedPages.count)")
            DispatchQueue.main.async {
                contentCache[cid] = fetched
                paragraphsCache[cid] = computedParas
                pagesCache[cid] = computedPages
                Log.debug(
                    "✅ ensurePrepared ready chapterId=\(cid) pages=\(computedPages.count)",
                    category: .prefetch
                )
                completion()
                perf.end(extra: "chapterId=\(cid)")
            }
        }
    }

    // 预取前后多章，提升左右滑动时的秒开体验
    private func prefetchAroundCurrent() {
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
                ensurePrepared(for: ch, isCritical: false) {}
            }
        }
        perf.end()
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
        let bounds = screenSize
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
                    arguments: [currentChapter.bookid]
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
                        id: currentChapter.bookid,
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
                currentBook = loaded
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
                    loadContent(for: target)
                    updateAdjacentRefs()
                    prefetchAroundCurrent()
                } else {
                    Log.debug(
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
            try Chapter
                .filter(Column("id") == id)
                .fetchOne(db)
        }
    }

    // MARK: - View helpers
    private var loadingView: some View {
        Text(String(localized: "reading.loading"))
            .font(.system(size: reading.fontSize))
            .foregroundColor(reading.textColor)
            .padding()
    }

    // 首次从书籍列表进入时的骨架占位视图（避免右侧白屏）
    private var initialSkeletonView: some View {
        // 参考真实排版的内边距与行距，确保进入时版式稳定
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // 第一页骨架
                VStack(alignment: .leading, spacing: reading.paragraphSpacing) {
                    // 章节标题骨架
                    HStack { Spacer() }
                        .frame(height: max(20, reading.fontSize * 1.2))
                        .frame(maxWidth: .infinity)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(reading.textColor.opacity(0.15))
                                .frame(width: max(0, geoSize().width * 0.5))
                        )
                        .padding(.top, chapterTitleTopPadding)
                        .padding(.bottom, chapterTitleBottomPadding)

                    // 若干段落骨架
                    ForEach(0..<6, id: \.self) { idx in
                        let widthFactor: CGFloat =
                            idx % 3 == 0 ? 0.95 : (idx % 3 == 1 ? 0.85 : 0.75)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(reading.textColor.opacity(0.12))
                            .frame(
                                width: max(0, geoSize().width * widthFactor),
                                height: max(12, reading.fontSize * 0.9)
                            )
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                // 第二页骨架（少量行，避免过度渲染）
                VStack(alignment: .leading, spacing: reading.paragraphSpacing) {
                    ForEach(0..<4, id: \.self) { idx in
                        let widthFactor: CGFloat = idx % 2 == 0 ? 0.9 : 0.7
                        RoundedRectangle(cornerRadius: 4)
                            .fill(reading.textColor.opacity(0.12))
                            .frame(
                                width: max(0, geoSize().width * widthFactor),
                                height: max(12, reading.fontSize * 0.9)
                            )
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
        .background(reading.backgroundColor)
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func pageView(pageIndex: Int) -> some View {
        let parts = paragraphsInPage(pageIndex)
        VStack(alignment: .leading, spacing: reading.paragraphSpacing) {

            // 显示章节标题
            if pageIndex == 0 {
                Text(currentChapter.title)
                    .font(.system(size: reading.fontSize * 1.2))
                    .foregroundColor(reading.textColor)
                    .lineSpacing(reading.lineSpacing)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .textSelection(.disabled)
                    .padding(.top, chapterTitleTopPadding)
                    .padding(.bottom, chapterTitleBottomPadding)
            }

            ForEach(parts.indices, id: \.self) { pIdx in
                Text(parts[pIdx])
                    .font(.system(size: reading.fontSize))
                    .foregroundColor(reading.textColor)
                    .lineSpacing(reading.lineSpacing)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.disabled)
            }
        }
        .contextMenu {
            Button {
                prepareAddFavorite(from: pageIndex)
            } label: {
                Label(
                    String(localized: "favorite.add_to_favorites"),
                    systemImage: "bookmark"
                )
            }
            .glassEffect(.clear.interactive())
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
        Log.debug(
            "📝 onPageAppear pageIndex=\(pageIndex) percent=\(percent) pages=\(pages.count) chapterId=\(currentChapter.id)"
        )
        saveProgress(percent: percent, pageIndex: pageIndex)
        // 阅读中触达更新时间（节流）
        touchCurrentBookUpdatedAt(throttleSeconds: 30)
    }

    private func pageAnchorId(_ index: Int) -> String { "page-\(index)" }

    // 统一滚动封装：主线程执行 + 极短延迟兜底，提升真机稳定性
    private func scrollToPage(
        _ index: Int,
        using proxy: ScrollViewProxy,
        animated: Bool
    ) {
        let anchorId = pageAnchorId(index)
        let perform = {
            if animated {
                withAnimation { proxy.scrollTo(anchorId, anchor: .top) }
            } else {
                proxy.scrollTo(anchorId, anchor: .top)
            }
        }
        DispatchQueue.main.async { perform() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { perform() }
    }

    private func restorePageIndex(for percent: Double, pagesCount: Int) -> Int {
        let clamped = max(0, min(1, percent))
        guard pagesCount > 1 else { return 0 }
        return Int(round(clamped * Double(pagesCount - 1)))
    }

    private func horizontalSwipeGesture(_ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                if abs(value.translation.width) > abs(value.translation.height)
                {
                    if !isHorizontalSwiping { isHorizontalSwiping = true }
                    let limit = size.width
                    let proposed = value.translation.width
                    dragOffset = max(-limit, min(limit, proposed))
                }
            }
            .onEnded { value in
                let threshold = min(120, size.width * 0.18)
                if abs(value.translation.width) <= abs(value.translation.height)
                {
                    withAnimation(.easeInOut) { dragOffset = 0 }
                    isHorizontalSwiping = false
                    return
                }
                if value.translation.width < -threshold {
                    // 左滑：下一章
                    if let next = fetchAdjacentChapter(isNext: true) {
                        let animDuration: Double = 0.2
                        withAnimation(.easeInOut(duration: animDuration)) {
                            dragOffset = -size.width
                        }
                        ensurePrepared(for: next, isCritical: true) {
                            let deadline = DispatchTime.now() + animDuration
                            DispatchQueue.main.asyncAfter(deadline: deadline) {
                                currentChapter = next
                                loadContent(for: next)
                                updateAdjacentRefs()
                                prefetchAroundCurrent()
                                // 无动画复位，避免二次滑入闪烁
                                dragOffset = 0
                                isHorizontalSwiping = false
                                // 切章立即触达一次
                                touchCurrentBookUpdatedAt(throttleSeconds: 0)
                            }
                        }
                    } else {
                        withAnimation(.easeInOut) { dragOffset = 0 }
                        isHorizontalSwiping = false
                    }
                } else if value.translation.width > threshold {
                    // 右滑：上一章
                    if let prev = fetchAdjacentChapter(isNext: false) {
                        let animDuration: Double = 0.2
                        withAnimation(.easeInOut(duration: animDuration)) {
                            dragOffset = size.width
                        }
                        ensurePrepared(for: prev, isCritical: true) {
                            let deadline = DispatchTime.now() + animDuration
                            DispatchQueue.main.asyncAfter(deadline: deadline) {
                                currentChapter = prev
                                loadContent(for: prev)
                                updateAdjacentRefs()
                                prefetchAroundCurrent()
                                // 无动画复位，避免二次滑入闪烁
                                dragOffset = 0
                                isHorizontalSwiping = false
                                // 切章立即触达一次
                                touchCurrentBookUpdatedAt(throttleSeconds: 0)
                            }
                        }
                    } else {
                        withAnimation(.easeInOut) { dragOffset = 0 }
                        isHorizontalSwiping = false
                    }
                } else {
                    withAnimation(.easeInOut) { dragOffset = 0 }
                    isHorizontalSwiping = false
                }
            }
    }

    // 双击左右区域切换章节（使用高优先级手势，避免被识别为两次单击）
    private func spatialDoubleTapGesture(geo: GeometryProxy) -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                // SpatialTapGesture.Value.location 为附着视图的本地坐标
                let point = value.location
                let width = geo.size.width
                let leftBoundary = width * 0.33
                let rightBoundary = width * 0.67

                if point.x <= leftBoundary {
                    // 双击左侧：上一章
                    navigateToAdjacentChapter(
                        isNext: false,
                        containerWidth: width
                    )
                } else if point.x >= rightBoundary {
                    // 双击右侧：下一章
                    navigateToAdjacentChapter(
                        isNext: true,
                        containerWidth: width
                    )
                } else {
                    // 中间区域双击不做处理（避免误触显示/隐藏控制条）
                }
            }
    }

    // 触达当前书籍的 updatedat（节流）
    private func touchCurrentBookUpdatedAt(throttleSeconds: Int) {
        let now = Int(Date().timeIntervalSince1970)
        if throttleSeconds <= 0
            || now - lastBookUpdatedAtTouchUnixTime >= throttleSeconds
        {
            DatabaseManager.shared.touchBookUpdatedAt(
                bookId: currentChapter.bookid,
                at: now
            )
            lastBookUpdatedAtTouchUnixTime = now
        }
    }

    // MARK: - 收藏相关
    private func prepareAddFavorite(from pageIndex: Int) {
        draftFavoritePageIndex = pageIndex
        let raw = pages[pageIndex]
        let condensed = raw.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(
                of: "\\s+",
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let maxLen = 120
        let preview =
            condensed.count > maxLen
            ? String(condensed.prefix(maxLen)) : condensed
        draftExcerpt = preview
        showAddFavoriteDialog = true
    }

    private func addFavorite(excerpt: String, pageIndex: Int) {
        let percent =
            pages.count > 1
            ? Double(pageIndex) / Double(pages.count - 1)
            : 0
        Log.debug(
            "⭐️ addFavorite bookId=\(currentChapter.bookid) chapterId=\(currentChapter.id) pageIndex=\(pageIndex) percent=\(percent) pages=\(pages.count)"
        )
        _ = DatabaseManager.shared.insertFavorite(
            bookId: currentChapter.bookid,
            chapterId: currentChapter.id,
            pageIndex: pageIndex,
            percent: percent,
            excerpt: excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func jump(to fav: Favorite) {
        Log.debug(
            "🎯 jump favorite id=\(fav.id) bookId=\(fav.bookid) chapterId=\(fav.chapterid) pageIndex=\(String(describing: fav.pageindex)) percent=\(String(describing: fav.percent)) currentChapterId=\(currentChapter.id) pages=\(pages.count)"
        )
        // 记录恢复意图：优先使用明确的页索引，其次才使用百分比，避免重复触发
        pendingRestorePageIndex = fav.pageindex
        pendingRestorePercent = fav.pageindex == nil ? fav.percent : nil
        pendingRestoreChapterId = fav.chapterid

        if fav.chapterid == currentChapter.id {
            // 当前章，直接触发分页恢复逻辑
            if let idx = fav.pageindex, !pages.isEmpty {
                DispatchQueue.main.async {
                    withAnimation {
                        // 使用 ScrollViewReader 的 anchor id 恢复
                        // 设置 pending 索引，交由 onChange/pages 执行；此处直接赋值也可
                        pendingRestorePageIndex = idx
                        pendingRestoreChapterId = currentChapter.id
                    }
                }
            }
            return
        }

        // 目标章，切换并加载后由 onChange 恢复
        if let target = fetchChapter(by: fav.chapterid) {
            currentChapter = target
            loadContent(for: target)
            updateAdjacentRefs()
            prefetchAroundCurrent()
        }
    }

    // 渲染某一章的内容（用于左右两侧的预览/滑入）
    @ViewBuilder
    private func chapterContentView(pagesArray: [String], title: String)
        -> some View
    {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(pagesArray.indices, id: \.self) { idx in
                    let parts = pagesArray[idx]
                        .split(
                            separator: "\n",
                            omittingEmptySubsequences: false
                        )
                        .map(String.init)
                    VStack(
                        alignment: .leading,
                        spacing: reading.paragraphSpacing
                    ) {
                        if idx == 0 {
                            Text(title)
                                .font(.system(size: reading.fontSize * 1.2))
                                .foregroundColor(reading.textColor)
                                .lineSpacing(reading.lineSpacing)
                                .multilineTextAlignment(.center)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .textSelection(.disabled)
                                .padding(.top, chapterTitleTopPadding)
                                .padding(.bottom, chapterTitleBottomPadding)
                        }
                        ForEach(parts.indices, id: \.self) { pIdx in
                            Text(parts[pIdx])
                                .font(.system(size: reading.fontSize))
                                .foregroundColor(reading.textColor)
                                .lineSpacing(reading.lineSpacing)
                                .multilineTextAlignment(.leading)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
            }
        }
        .background(reading.backgroundColor)
        .scrollIndicators(.hidden)
    }
}
