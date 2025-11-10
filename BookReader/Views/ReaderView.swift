import GRDB
import SwiftUI

struct ReaderView: View {
    // MARK: - Dependencies
    @EnvironmentObject private var db: DatabaseManager
    @StateObject private var viewModel: ReaderViewModel
    @EnvironmentObject var progressStore: ProgressStore
    @EnvironmentObject private var reading: ReadingSettings

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - UI State
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

    @State private var showControls: Bool = false

    // 收藏
    @State private var showFavorites: Bool = false
    @State private var showAddFavoriteDialog: Bool = false
    @State private var draftExcerpt: String = ""
    @State private var draftFavoritePageIndex: Int? = nil
    @State private var showBookInfo: Bool = false

    // 边界提示（第一章/最后一章）
    @State private var showEdgeAlert: Bool = false
    @State private var edgeAlertMessage: String = ""

    @State private var allowContextMenu = true

    @Namespace private var controlsNamespace

    init(chapter: Chapter, isInitialFromBookList: Bool = false) {
        _viewModel = StateObject(
            wrappedValue: ReaderViewModel(
                initialChapter: chapter,
                isInitialFromBookList: isInitialFromBookList
            )
        )
    }

    // MARK: - Body
    var body: some View {
        GeometryReader { geo in
            GlassEffectContainer {
                ZStack(alignment: .top) {
                    leftPreviewView(geo: geo)
                    contentScrollView(geo: geo)
                    rightPreviewView(geo: geo)
                }
                .toolbar(.hidden, for: .navigationBar)
                .background(reading.backgroundColor)
                .overlay(alignment: .top) {
                    if showControls {
                        topControlsView()
                    }
                }
                .overlay(alignment: .bottom) {
                    if showControls {
                        bottomControlsView(geo: geo)
                    }
                }
                .overlay {
                    if showAddFavoriteDialog {
                        TextFieldDialog(
                            title: String(
                                localized: "favorite.add_to_favorites"
                            ),
                            placeholder: String(
                                localized:
                                    "favorite.add_to_favorites_placeholder"
                            ),
                            text: $draftExcerpt,
                            onCancel: {
                                showAddFavoriteDialog = false
                            },
                            onSave: {
                                let pageIdx =
                                    draftFavoritePageIndex
                                    ?? viewModel.currentVisiblePageIndex
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
                        if let book = viewModel.currentBook {
                            ChapterListView(
                                book: book,
                                onSelect: { ch in
                                    viewModel.currentChapter = ch
                                    viewModel.loadContent(
                                        for: ch,
                                        reading: reading
                                    )
                                    // 从目录跳转时立即触达
                                    viewModel.touchBookUpdatedAt(
                                        throttleSeconds: 0
                                    )
                                    showCatalog = false
                                },
                                initialChapterId: viewModel.currentChapter.id
                            )
                        } else {
                            Text(
                                String(localized: "reading.book_index_loading")
                            )
                        }
                    }
                }
                .sheet(isPresented: $showSettings) {
                    ReaderSettingsView()
                }
                .sheet(isPresented: $showFavorites) {
                    FavoritesView(bookId: viewModel.currentChapter.bookid) {
                        fav in
                        jump(to: fav)
                        showFavorites = false
                    }
                }
                .sheet(isPresented: $showBookInfo) {
                    if let book = viewModel.currentBook {
                        BookInfoView(
                            book: book,
                            progressText: viewModel.readingProgressText(
                                for: book.id,
                                progressStore: progressStore,
                                includePercent: true
                            )
                        )
                    } else {
                        ProgressView()
                            .padding()
                    }
                }
                .alert(isPresented: $showEdgeAlert) {
                    Alert(
                        title: Text(edgeAlertMessage),
                        dismissButton: .default(
                            Text(String(localized: "btn.ok"))
                        )
                    )
                }
                .contentShape(Rectangle())
                .highPriorityGesture(spatialDoubleTapGesture(geo: geo))
                .simultaneousGesture(horizontalSwipeGesture(geo: geo))
                .onTapGesture {
                    withAnimation { showControls.toggle() }
                }
                .onAppear {
                    // 初始化依赖、首屏加载、预取与进度恢复
                    let perf = PerfTimer(
                        "ReaderView.onAppear",
                        category: .performance
                    )
                    viewModel.attachDatabase(db)
                    Log.debug(
                        "📖 ReaderView.onAppear enter chapterId=\(viewModel.currentChapter.id) bookId=\(viewModel.currentChapter.bookid) pages=\(viewModel.pages.count) needsInitialRestore=\(viewModel.needsInitialRestore) pendingRestorePercent=\(String(describing: viewModel.pendingRestorePercent)) pendingRestorePageIndex=\(String(describing: viewModel.pendingRestorePageIndex))",
                        category: .reader
                    )

                    viewModel.setScreenSize(geo.size)

                    viewModel.loadContent(
                        for: viewModel.currentChapter,
                        reading: reading
                    )
                    viewModel.loadCurrentBook()
                    viewModel.updateAdjacentRefs()
                    if viewModel.needsInitialRestore {
                        viewModel.restoreLastProgressIfNeeded(
                            progressStore: progressStore
                        )
                    }
                    // 进入阅读页即触达一次（节流保护）
                    viewModel.touchBookUpdatedAt(throttleSeconds: 30)

                    // 首帧后小延时扩大预取半径并进行二次预取（避免首屏压力）
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        viewModel.prefetchRadius = 3
                        viewModel.prefetchAroundCurrent(
                            config: viewModel.snapshotPaginationConfig(
                                reading: reading
                            )
                        )
                    }
                    perf.end()
                }
                .onChange(of: geo.size) { _, newSize in
                    viewModel.setScreenSize(newSize)
                }
                .onReceive(
                    NotificationCenter.default.publisher(for: .dismissAllModals)
                ) { _ in
                    // 关闭所有模态视图和控制条
                    showCatalog = false
                    showSettings = false
                    showFavorites = false
                    showAddFavoriteDialog = false
                    showBookInfo = false
                    showControls = false
                    allowContextMenu = false
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        // 重新激活时，延迟恢复上下文菜单，确保 UI 已稳定
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            allowContextMenu = true
                        }
                    }
                }
            }
        }
    }

    private func geoSize() -> CGSize {
        let bounds = viewModel.screenSize
        // 减去大致的安全区/导航区和内边距
        return CGSize(width: bounds.width - 32, height: bounds.height - 140)
    }

    // MARK: - Extracted Views (左右预览/中间内容)
    @ViewBuilder
    private func chapterContentView(pagesArray: [[String]], title: String)
        -> some View
    {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(pagesArray.indices, id: \.self) { idx in
                    let parts = pagesArray[idx]
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

    @ViewBuilder
    private func leftPreviewView(geo: GeometryProxy) -> some View {
        // 左侧上一章预览（横滑时展示）
        if abs(dragOffset) > 0.1,
            let prev = viewModel.prevChapterRef,
            let prevPages = viewModel.pagesCache[prev.id]
        {
            let parts =
                viewModel.pagesPartsCache[prev.id]
                ?? prevPages.map {
                    $0.split(separator: "\n", omittingEmptySubsequences: false)
                        .map(String.init)
                }
            chapterContentView(pagesArray: parts, title: prev.title)
                .offset(x: -geo.size.width + dragOffset)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func rightPreviewView(geo: GeometryProxy) -> some View {
        // 右侧下一章预览（横滑时展示）
        if abs(dragOffset) > 0.1,
            let next = viewModel.nextChapterRef,
            let nextPages = viewModel.pagesCache[next.id]
        {
            let parts =
                viewModel.pagesPartsCache[next.id]
                ?? nextPages.map {
                    $0.split(separator: "\n", omittingEmptySubsequences: false)
                        .map(String.init)
                }
            chapterContentView(pagesArray: parts, title: next.title)
                .offset(x: geo.size.width + dragOffset)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func contentScrollView(geo: GeometryProxy) -> some View {
        // 中间：当前章节的内容滚动与分页恢复
        ScrollViewReader { proxy in
            ScrollView {
                if !viewModel.pages.isEmpty {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.pages.indices, id: \.self) { idx in
                            pageView(pageIndex: idx)
                                .id(pageAnchorId(idx))
                        }
                    }
                } else {
                    if viewModel.showInitialSkeleton {
                        initialSkeletonView
                    } else {
                        loadingView
                    }
                }
            }
            .background(reading.backgroundColor)
            .scrollIndicators(isHorizontalSwiping ? .hidden : .visible)
            .id(viewModel.currentChapter.id)
            .offset(x: dragOffset)
            .onChange(of: viewModel.pages) { oldPages, newPages in
                Log.debug(
                    "📖 onChange pages: old=\(oldPages.count) new=\(newPages.count) pendingRestorePercent=\(String(describing: viewModel.pendingRestorePercent)) pendingRestorePageIndex=\(String(describing: viewModel.pendingRestorePageIndex)) chapterId=\(viewModel.currentChapter.id)"
                )
                guard !newPages.isEmpty else {
                    Log.debug("📖 onChange pages: pages empty, skip")
                    return
                }
                if viewModel.showInitialSkeleton {
                    viewModel.showInitialSkeleton = false
                }
                // 统一恢复入口（根据 pending 状态恢复至指定页/百分比）
                let restored = applyPendingRestoreIfPossible(
                    using: proxy,
                    pagesCount: newPages.count,
                    animated: true
                )
                if !restored {
                    Log.debug("📖 onChange pages: no pending restore, skip")
                }
            }
            // 收藏跳转：同章节情况下也能立即滚动
            .onChange(of: viewModel.pendingRestorePageIndex) {
                oldValue,
                newValue in
                guard newValue != nil, !viewModel.pages.isEmpty else { return }
                let restored = applyPendingRestoreIfPossible(
                    using: proxy,
                    pagesCount: viewModel.pages.count,
                    animated: true
                )
                if !restored {
                    Log.debug("📖 onChange pendingRestorePageIndex: no-op")
                }
            }
            .onChange(of: viewModel.pendingRestorePercent) {
                oldValue,
                newValue in
                guard newValue != nil, !viewModel.pages.isEmpty else { return }
                let restored = applyPendingRestoreIfPossible(
                    using: proxy,
                    pagesCount: viewModel.pages.count,
                    animated: true
                )
                if !restored {
                    Log.debug("📖 onChange pendingRestorePercent: no-op")
                }
            }
            // 章节切换完成的兜底：若目标章与当前章一致且 pages 已就绪，则立即恢复
            .onChange(of: viewModel.currentChapter.id) { oldId, newId in
                Log.debug(
                    "📖 onChange currentChapterId old=\(oldId) new=\(newId) pendingChapter=\(String(describing: viewModel.pendingRestoreChapterId)) pendingPageIndex=\(String(describing: viewModel.pendingRestorePageIndex)) pendingPercent=\(String(describing: viewModel.pendingRestorePercent)) pages=\(viewModel.pages.count)"
                )
                guard let targetChapterId = viewModel.pendingRestoreChapterId,
                    targetChapterId == newId
                else { return }
                guard !viewModel.pages.isEmpty else { return }
                _ = applyPendingRestoreIfPossible(
                    using: proxy,
                    pagesCount: viewModel.pages.count,
                    animated: true
                )
            }
            .onAppear {
                Log.debug(
                    "📖 ScrollViewReader.onAppear pages=\(viewModel.pages.count) needsInitialRestore=\(viewModel.needsInitialRestore) pendingRestorePercent=\(String(describing: viewModel.pendingRestorePercent)) pendingRestorePageIndex=\(String(describing: viewModel.pendingRestorePageIndex)) chapterId=\(viewModel.currentChapter.id)"
                )
                if viewModel.needsInitialRestore {
                    viewModel.restoreLastProgressIfNeeded(
                        progressStore: progressStore
                    )
                }
                if !viewModel.pages.isEmpty {
                    let restored = applyPendingRestoreIfPossible(
                        using: proxy,
                        pagesCount: viewModel.pages.count,
                        animated: false
                    )
                    if !restored {
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
        namespace: Namespace.ID,
        applyGlass: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        // 圆形图标按钮（带玻璃效果）
        Button(action: action) {
            Image(systemName: systemName)
                .foregroundColor(reading.textColor)
                .actionIcon()
        }
        .glassCircleButton(
            id: title,
            namespace: namespace,
            foreground: reading.textColor,
            background: reading.backgroundColor,
            applyGlass: applyGlass
        )
        .accessibilityLabel(
            NSLocalizedString(title, comment: "")
        )
    }

    @ViewBuilder
    private func bottomControlsView(geo: GeometryProxy) -> some View {
        // 底部控制条（上一章 / 目录 / 收藏 / 设置 / 下一章）
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
                    namespace: controlsNamespace,
                    applyGlass: false
                ) {
                    showCatalog = true
                }

                circularButton(
                    systemName: "bookmark",
                    title: "btn.favorite",
                    namespace: controlsNamespace,
                    applyGlass: false
                ) {
                    showFavorites = true
                }

                circularButton(
                    systemName: "gear",
                    title: "btn.setting",
                    namespace: controlsNamespace,
                    applyGlass: false
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

    @ViewBuilder
    private func topControlsView() -> some View {
        // 顶部控制条（返回 / 章节标题 / 书籍信息）
        HStack {
            circularButton(
                systemName: "chevron.left",
                title: "btn.back",
                namespace: controlsNamespace
            ) {
                dismiss()
            }

            Text(viewModel.currentChapter.title)
                .font(.headline)
                .foregroundColor(reading.textColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 8)
                .padding(.vertical, 11)
                .background(reading.backgroundColor.opacity(0.8))
                .cornerRadius(22)
                .glassEffect(.clear.interactive())

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

    private func navigateToAdjacentChapter(
        isNext: Bool,
        containerWidth: CGFloat
    ) {
        guard let target = viewModel.fetchAdjacentChapter(isNext: isNext) else {
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
        viewModel.ensurePrepared(
            for: target,
            isCritical: true,
            config: viewModel.snapshotPaginationConfig(reading: reading)
        ) {
            // 在移出动画结束后切换章节，并无动画归零偏移，避免“再次滑入”的闪烁
            let deadline = DispatchTime.now() + animDuration
            DispatchQueue.main.asyncAfter(deadline: deadline) {
                viewModel.currentChapter = target
                viewModel.loadContent(for: target, reading: reading)
                viewModel.updateAdjacentRefs()
                viewModel.prefetchAroundCurrent(
                    config: viewModel.snapshotPaginationConfig(reading: reading)
                )
                // 重置偏移（无动画），此时右侧/左侧预览已参与过滑动，不再二次滑入
                dragOffset = 0
                // 按钮切章也触达
                viewModel.touchBookUpdatedAt(throttleSeconds: 0)
            }
        }
    }

    // MARK: - 骨架/分页页视图
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
        // 单页内容渲染（包含第一页的章节标题）
        let parts = paragraphsInPage(pageIndex)
        let pageContent = VStack(
            alignment: .leading,
            spacing: reading.paragraphSpacing
        ) {
            // 显示章节标题
            if pageIndex == 0 {
                Text(viewModel.currentChapter.title)
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

        let finalView =
            pageContent
            .padding(.horizontal)
            .padding(.vertical, 8)
            .onAppear { onPageAppear(pageIndex) }

        if allowContextMenu {
            finalView.contextMenu {
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
        } else {
            finalView
        }
    }

    private func paragraphsInPage(_ index: Int) -> [String] {
        // 从预切分缓存中读取指定页的段落数组
        if index < 0 || index >= viewModel.pagesParts.count { return [] }
        return viewModel.pagesParts[index]
    }

    private func onPageAppear(_ pageIndex: Int) {
        // 单页出现时更新可见页索引、保存进度并做节流触达
        viewModel.currentVisiblePageIndex = pageIndex
        let percent =
            viewModel.pages.count > 1
            ? Double(pageIndex) / Double(viewModel.pages.count - 1)
            : 0
        Log.debug(
            "📝 onPageAppear pageIndex=\(pageIndex) percent=\(percent) pages=\(viewModel.pages.count) chapterId=\(viewModel.currentChapter.id)"
        )
        viewModel.saveProgress(
            progressStore: progressStore,
            percent: percent,
            pageIndex: pageIndex
        )
        // 阅读中触达更新时间（节流）
        viewModel.touchBookUpdatedAt(throttleSeconds: 30)
    }

    private func pageAnchorId(_ index: Int) -> String { "page-\(index)" }

    // 统一滚动封装：主线程执行 + 极短延迟兜底，提升真机稳定性
    private func scrollToPage(
        _ index: Int,
        using proxy: ScrollViewProxy,
        animated: Bool
    ) {
        // 封装滚动并加极短延时兜底，提升真机稳定性
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
        // 将 0~1 百分比映射为页索引
        let clamped = max(0, min(1, percent))
        guard pagesCount > 1 else { return 0 }
        return Int(round(clamped * Double(pagesCount - 1)))
    }

    // 统一的恢复助手：根据 pendingRestore* 决定是否恢复并落盘
    private func applyPendingRestoreIfPossible(
        using proxy: ScrollViewProxy,
        pagesCount: Int,
        animated: Bool
    ) -> Bool {
        let shouldApplyRestore =
            (viewModel.pendingRestoreChapterId == nil)
            || (viewModel.pendingRestoreChapterId == viewModel.currentChapter.id)
        guard shouldApplyRestore, pagesCount > 0 else { return false }

        if let idx0 = viewModel.pendingRestorePageIndex {
            let idx = max(0, min(pagesCount - 1, idx0))
            Log.debug(
                "📖 restore via helper (pageIndex) → scrollTo pageIndex=\(idx)"
            )
            scrollToPage(idx, using: proxy, animated: animated)
            viewModel.pendingRestorePageIndex = nil
            viewModel.pendingRestorePercent = nil
            viewModel.pendingRestoreChapterId = nil
            viewModel.currentVisiblePageIndex = idx
            let computedPercent =
                pagesCount > 1 ? Double(idx) / Double(pagesCount - 1) : 0
            viewModel.saveProgress(
                progressStore: progressStore,
                percent: computedPercent,
                pageIndex: idx
            )
            return true
        } else if let percent = viewModel.pendingRestorePercent {
            let idx = restorePageIndex(for: percent, pagesCount: pagesCount)
            Log.debug(
                "📖 restore via helper (percent) → scrollTo pageIndex=\(idx) percent=\(percent)"
            )
            scrollToPage(idx, using: proxy, animated: animated)
            viewModel.pendingRestorePercent = nil
            viewModel.pendingRestoreChapterId = nil
            viewModel.currentVisiblePageIndex = idx
            let computedPercent =
                pagesCount > 1 ? Double(idx) / Double(pagesCount - 1) : 0
            viewModel.saveProgress(
                progressStore: progressStore,
                percent: computedPercent,
                pageIndex: idx
            )
            return true
        }
        return false
    }

    // MARK: - Gestures
    private func horizontalSwipeGesture(geo: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if abs(value.translation.width) > abs(value.translation.height)
                {
                    if !isHorizontalSwiping { isHorizontalSwiping = true }
                    let limit = geo.size.width
                    let proposed = value.translation.width
                    dragOffset = max(-limit, min(limit, proposed))
                }
            }
            .onEnded { value in
                let threshold = min(120, geo.size.width * 0.18)
                if abs(value.translation.width) <= abs(value.translation.height)
                {
                    withAnimation(.easeInOut) { dragOffset = 0 }
                    isHorizontalSwiping = false
                    return
                }
                if value.translation.width < -threshold {
                    // 左滑：下一章
                    if let next = viewModel.fetchAdjacentChapter(isNext: true) {
                        let animDuration: Double = 0.2
                        withAnimation(.easeInOut(duration: animDuration)) {
                            dragOffset = -geo.size.width
                        }
                        viewModel.ensurePrepared(
                            for: next,
                            isCritical: true,
                            config: viewModel.snapshotPaginationConfig(
                                reading: reading
                            )
                        ) {
                            let deadline = DispatchTime.now() + animDuration
                            DispatchQueue.main.asyncAfter(deadline: deadline) {
                                viewModel.currentChapter = next
                                viewModel.loadContent(
                                    for: next,
                                    reading: reading
                                )
                                viewModel.updateAdjacentRefs()
                                viewModel.prefetchAroundCurrent(
                                    config: viewModel.snapshotPaginationConfig(
                                        reading: reading
                                    )
                                )
                                // 无动画复位，避免二次滑入闪烁
                                dragOffset = 0
                                isHorizontalSwiping = false
                                // 切章立即触达一次
                                viewModel.touchBookUpdatedAt(throttleSeconds: 0)
                            }
                        }
                    } else {
                        withAnimation(.easeInOut) { dragOffset = 0 }
                        isHorizontalSwiping = false
                    }
                } else if value.translation.width > threshold {
                    // 右滑：上一章
                    if let prev = viewModel.fetchAdjacentChapter(isNext: false)
                    {
                        let animDuration: Double = 0.2
                        withAnimation(.easeInOut(duration: animDuration)) {
                            dragOffset = geo.size.width
                        }
                        viewModel.ensurePrepared(
                            for: prev,
                            isCritical: true,
                            config: viewModel.snapshotPaginationConfig(
                                reading: reading
                            )
                        ) {
                            let deadline = DispatchTime.now() + animDuration
                            DispatchQueue.main.asyncAfter(deadline: deadline) {
                                viewModel.currentChapter = prev
                                viewModel.loadContent(
                                    for: prev,
                                    reading: reading
                                )
                                viewModel.updateAdjacentRefs()
                                viewModel.prefetchAroundCurrent(
                                    config: viewModel.snapshotPaginationConfig(
                                        reading: reading
                                    )
                                )
                                // 无动画复位，避免二次滑入闪烁
                                dragOffset = 0
                                isHorizontalSwiping = false
                                // 切章立即触达一次
                                viewModel.touchBookUpdatedAt(throttleSeconds: 0)
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

    // MARK: - Favorites
    private func prepareAddFavorite(from pageIndex: Int) {
        // 打开收藏对话框并生成默认摘录预览
        draftFavoritePageIndex = pageIndex
        let raw = viewModel.pages[pageIndex]
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
        // 调用 VM 写入收藏
        let percent =
            viewModel.pages.count > 1
            ? Double(pageIndex) / Double(viewModel.pages.count - 1)
            : 0
        Log.debug(
            "⭐️ addFavorite bookId=\(viewModel.currentChapter.bookid) chapterId=\(viewModel.currentChapter.id) pageIndex=\(pageIndex) percent=\(percent) pages=\(viewModel.pages.count)"
        )
        viewModel.addFavorite(excerpt: excerpt, pageIndex: pageIndex)
    }

    private func jump(to fav: Favorite) {
        // 从收藏跳转到指定章节与位置（优先 pageIndex，退化到 percent）
        Log.debug(
            "🎯 jump favorite id=\(fav.id) bookId=\(fav.bookid) chapterId=\(fav.chapterid) pageIndex=\(String(describing: fav.pageindex)) percent=\(String(describing: fav.percent)) currentChapterId=\(viewModel.currentChapter.id) pages=\(viewModel.pages.count)"
        )
        // 记录恢复意图：优先使用明确的页索引，其次才使用百分比，避免重复触发
        viewModel.pendingRestorePageIndex = fav.pageindex
        viewModel.pendingRestorePercent =
            fav.pageindex == nil ? fav.percent : nil
        viewModel.pendingRestoreChapterId = fav.chapterid

        if fav.chapterid == viewModel.currentChapter.id {
            // 当前章，直接触发分页恢复逻辑
            if let idx = fav.pageindex, !viewModel.pages.isEmpty {
                DispatchQueue.main.async {
                    withAnimation {
                        // 使用 ScrollViewReader 的 anchor id 恢复
                        // 设置 pending 索引，交由 onChange/pages 执行；此处直接赋值也可
                        viewModel.pendingRestorePageIndex = idx
                        viewModel.pendingRestoreChapterId =
                            viewModel.currentChapter.id
                    }
                }
            }
            return
        }

        // 目标章，切换并加载后由 onChange 恢复
        if let target = viewModel.fetchChapter(by: fav.chapterid) {
            viewModel.currentChapter = target
            viewModel.pendingRestorePageIndex = fav.pageindex
            viewModel.pendingRestorePercent =
                fav.pageindex == nil ? fav.percent : nil
            viewModel.pendingRestoreChapterId = fav.chapterid
            viewModel.loadContent(for: target, reading: reading)
            viewModel.updateAdjacentRefs()
            viewModel.prefetchAroundCurrent(
                config: viewModel.snapshotPaginationConfig(reading: reading)
            )
        }
    }

}
