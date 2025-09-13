import GRDB
import SwiftUI

struct ReaderView: View {
    @State private var currentBook: Book?
    @State private var currentChapter: Chapter
    @State private var content: Content?
    @EnvironmentObject var progressStore: ProgressStore
    @EnvironmentObject private var reading: ReadingSettings
    // 使用 @AppStorage 作为持久化源
    @AppStorage(DefaultsKeys.readerFontSize) private var storedFontSize:
        Double = 16
    @AppStorage(DefaultsKeys.readerLineSpacing) private var storedLineSpacing:
        Double = 8
    @AppStorage(DefaultsKeys.readerParagraphSpacing) private
        var storedParagraphSpacing: Double = 16
    @AppStorage(DefaultsKeys.readerBackgroundColor) private var storedBgHex:
        String = "#FFFFFF"
    @AppStorage(DefaultsKeys.readerTextColor) private var storedTextHex:
        String = "#000000"
    @AppStorage(DefaultsKeys.readerDebugLoggingEnabled) private
        var debugEnabled: Bool = false

    // 目录
    @State private var showCatalog: Bool = false
    // 阅读设置
    @State private var showSettings: Bool = false
    // 直接使用 ReadingSettings 提供的值，无需派生状态

    // 拖拽偏移（用于左右滑动动画）
    @State private var dragOffset: CGFloat = 0
    // 是否处于左右滑动中（用于临时隐藏滚动条）
    @State private var isHorizontalSwiping: Bool = false

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
    @State private var pendingRestoreChapterId: Int? = nil
    // 触达书籍更新时间节流
    @State private var lastBookUpdatedAtTouchUnixTime: Int = 0

    // 收藏
    @State private var showFavorites: Bool = false
    @State private var favorites: [FavoriteRow] = []
    @State private var showAddFavoriteDialog: Bool = false
    @State private var draftExcerpt: String = ""
    @State private var draftFavoritePageIndex: Int? = nil
    @State private var showBookInfo: Bool = false

    // 边界提示（第一章/最后一章）
    @State private var showEdgeAlert: Bool = false
    @State private var edgeAlertMessage: String = ""

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
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(currentChapter.title)
                        .font(.headline)
                        .foregroundColor(reading.textColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showBookInfo = true
                    } label: {
                        Image(systemName: "book")
                    }
                    .accessibilityLabel("图书信息")
                }
            }
            .tint(reading.textColor)
            .background(reading.backgroundColor)
            .overlay(alignment: .bottom) { bottomControlsView(geo: geo) }
            .overlay {
                if showAddFavoriteDialog {
                    TextFieldDialog(
                        title: "添加到收藏",
                        placeholder: "为本次收藏写点备注（可选）",
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
                        Text("正在加载目录...")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                ReaderSettingsView()
            }
            .sheet(isPresented: $showFavorites) {
                NavigationStack {
                    List {
                        ForEach(favorites) { row in
                            Button {
                                jump(to: row.favorite)
                                showFavorites = false
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(row.chapterTitle)
                                        .font(.headline)
                                    if let ex = row.favorite.excerpt,
                                        !ex.isEmpty
                                    {
                                        Text(ex)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                    if let idx = row.favorite.pageindex {
                                        Text("第 \(idx + 1) 页")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .swipeActions(
                                edge: .trailing,
                                allowsFullSwipe: true
                            ) {
                                Button(role: .destructive) {
                                    deleteFavorite(id: row.favorite.id)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .navigationTitle("收藏夹")
                    .onAppear { loadFavorites() }
                }
            }
            .sheet(isPresented: $showBookInfo) {
                bookInfo()
            }
            .alert(isPresented: $showEdgeAlert) {
                Alert(
                    title: Text(edgeAlertMessage),
                    dismissButton: .default(Text("我知道了"))
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
                loadCurrentBook()
                updateAdjacentRefs()
                prefetchAroundCurrent()
                if needsInitialRestore {
                    restoreLastProgressIfNeeded()
                }
                // 进入阅读页即触达一次（节流保护）
                touchCurrentBookUpdatedAt(throttleSeconds: 30)

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
            }
            // 设置由 ReadingSettings 驱动，无需本地同步
            .onDisappear {
                // 移除通知监听器
                NotificationCenter.default.removeObserver(self)
            }
        }
    }

    // MARK: - Extracted Views
    @ViewBuilder
    private func bookInfo() -> some View {
        NavigationStack {
            if let book = currentBook {
                List {
                    Section("图书信息") {
                        Text("书名：\(book.title)")
                        Text("作者：\(book.author)")
                        if !book.category.isEmpty {
                            Text("分类：\(book.category)")
                        }
                        Text("字数：\(formatWordCount(book.wordcount))字")
                        if !book.latest.isEmpty {
                            Text("最新章节：\(book.latest)")
                        }
                        let updatedDate = Date(
                            timeIntervalSince1970: TimeInterval(book.updatedat)
                        )
                        HStack(spacing: 4) {
                            Text("更新时间：")
                            Text(updatedDate, style: .date)
                            Text(updatedDate, style: .time)
                        }
                        Text("完结：\(book.isfinished == 1 ? "是" : "否")")
                    }
                }
                .navigationTitle("图书信息")
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在加载...")
                }
                .padding()
                .navigationTitle("图书信息")
            }
        }
    }

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
            .scrollIndicators(isHorizontalSwiping ? .hidden : .visible)
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
                // 仅当目标章节就是当前章节时才应用恢复
                let shouldApplyRestore =
                    (pendingRestoreChapterId == nil)
                    || (pendingRestoreChapterId == currentChapter.id)
                guard shouldApplyRestore else {
                    dlog(
                        "📖 onChange pages: pending for chapterId=\(String(describing: pendingRestoreChapterId)), current=\(currentChapter.id), skip"
                    )
                    return
                }
                if let idx0 = pendingRestorePageIndex {
                    let idx = max(0, min(newPages.count - 1, idx0))
                    dlog(
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
                    dlog(
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
                    dlog("📖 onChange pages: no pending restore, skip")
                }
            }
            // 收藏跳转：同章节情况下也能立即滚动
            .onChange(of: pendingRestorePageIndex) { oldValue, newValue in
                guard let idx0 = newValue, !pages.isEmpty else { return }
                let shouldApplyRestore =
                    (pendingRestoreChapterId == nil)
                    || (pendingRestoreChapterId == currentChapter.id)
                guard shouldApplyRestore else {
                    dlog(
                        "📖 onChange pendingRestorePageIndex: pending for chapterId=\(String(describing: pendingRestoreChapterId)), current=\(currentChapter.id), skip"
                    )
                    return
                }
                let idx = max(0, min(pages.count - 1, idx0))
                dlog(
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
                    dlog(
                        "📖 onChange pendingRestorePercent: pending for chapterId=\(String(describing: pendingRestoreChapterId)), current=\(currentChapter.id), skip"
                    )
                    return
                }
                let idx = restorePageIndex(
                    for: percent,
                    pagesCount: pages.count
                )
                dlog(
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
                dlog(
                    "📖 onChange currentChapterId old=\(oldId) new=\(newId) pendingChapter=\(String(describing: pendingRestoreChapterId)) pendingPageIndex=\(String(describing: pendingRestorePageIndex)) pendingPercent=\(String(describing: pendingRestorePercent)) pages=\(pages.count)"
                )
                guard let targetChapterId = pendingRestoreChapterId,
                    targetChapterId == newId
                else { return }
                if let idx0 = pendingRestorePageIndex, !pages.isEmpty {
                    let idx = max(0, min(pages.count - 1, idx0))
                    dlog(
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
                    dlog(
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
                        dlog(
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
            HStack(spacing: 0) {
                Button {
                    navigateToAdjacentChapter(
                        isNext: false,
                        containerWidth: geo.size.width
                    )
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("上一章").font(.caption)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .contentShape(Rectangle())

                Button {
                    showCatalog = true
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "list.bullet")
                        Text("目录").font(.caption)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .contentShape(Rectangle())

                Button {
                    showFavorites = true
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "bookmark")
                        Text("收藏").font(.caption)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .contentShape(Rectangle())

                Button {
                    showSettings = true
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "gearshape")
                        Text("设置").font(.caption)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .contentShape(Rectangle())

                Button {
                    navigateToAdjacentChapter(
                        isNext: true,
                        containerWidth: geo.size.width
                    )
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "chevron.right")
                        Text("下一章").font(.caption)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .contentShape(Rectangle())
            }
            .foregroundColor(reading.textColor)
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
                    fontSize: CGFloat(reading.fontSize),
                    lineSpacing: CGFloat(reading.lineSpacing)
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
                fontSize: CGFloat(reading.fontSize),
                lineSpacing: CGFloat(reading.lineSpacing)
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
            edgeAlertMessage = isNext ? "已是最后一章。" : "已是第一章。"
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
                // 按钮切章也触达
                touchCurrentBookUpdatedAt(throttleSeconds: 0)
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
                fontSize: CGFloat(reading.fontSize),
                lineSpacing: CGFloat(reading.lineSpacing)
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
            try Chapter
                .filter(Column("id") == id)
                .fetchOne(db)
        }
    }

    // MARK: - View helpers
    private var loadingView: some View {
        Text("加载中...")
            .font(.system(size: reading.fontSize))
            .foregroundColor(reading.textColor)
            .padding()
    }

    @ViewBuilder
    private func pageView(pageIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(pages[pageIndex])
                .font(.system(size: reading.fontSize))
                .foregroundColor(reading.textColor)
                .lineSpacing(reading.lineSpacing)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .contextMenu {
                    Button {
                        prepareAddFavorite(from: pageIndex)
                    } label: {
                        Label("添加到收藏", systemImage: "bookmark")
                    }
                }
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
        DragGesture()
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
                let threshold = size.width * 0.25
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
                        ensurePrepared(for: next) {
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
                        ensurePrepared(for: prev) {
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

    private func dlog(_ message: String) {
        if debugEnabled {
            print(message)
        }
    }

    // MARK: - 收藏相关
    private func loadFavorites() {
        favorites = DatabaseManager.shared.fetchFavorites(
            bookId: currentChapter.bookid
        )
    }

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
        dlog(
            "⭐️ addFavorite bookId=\(currentChapter.bookid) chapterId=\(currentChapter.id) pageIndex=\(pageIndex) percent=\(percent) pages=\(pages.count)"
        )
        _ = DatabaseManager.shared.insertFavorite(
            bookId: currentChapter.bookid,
            chapterId: currentChapter.id,
            pageIndex: pageIndex,
            percent: percent,
            excerpt: excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        loadFavorites()
    }

    private func deleteFavorite(id: Int) {
        DatabaseManager.shared.deleteFavorite(id: id)
        loadFavorites()
    }

    private func jump(to fav: Favorite) {
        dlog(
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
    private func chapterContentView(pagesArray: [String]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(pagesArray.indices, id: \.self) { idx in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(pagesArray[idx])
                            .font(.system(size: reading.fontSize))
                            .foregroundColor(reading.textColor)
                            .lineSpacing(reading.lineSpacing)
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

    private func formatWordCount(_ wordCount: Int) -> String {
        if wordCount < 10000 {
            return "\(wordCount)"
        } else {
            let tenThousands = wordCount / 10000
            return "\(tenThousands)万"
        }
    }
}
