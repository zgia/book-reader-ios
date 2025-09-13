import GRDB
import SwiftUI

struct ChapterListView: View {
    var book: Book
    var onSelect: ((Chapter) -> Void)? = nil
    @State private var chapters: [Chapter] = []
    @State private var volumes: [Volume] = []
    @State private var chaptersByVolume: [Int: [Chapter]] = [:]  // volumeId -> chapters
    @State private var searchText = ""
    var initialChapterId: Int? = nil
    @State private var didAutoScroll = false

    var body: some View {
        ScrollViewReader { proxy in
            Group {
                if searchText.isEmpty {
                    ScrollView {
                        LazyVStack(
                            alignment: .leading,
                            pinnedViews: [.sectionHeaders]
                        ) {
                            ForEach(volumes) { v in
                                Section(
                                    header:
                                        ZStack(alignment: .leading) {
                                            // 提供背景以避免吸顶时文字与内容叠加
                                            Color(.systemBackground)
                                            VStack(
                                                alignment: .leading,
                                                spacing: 4
                                            ) {
                                                Text(v.title).font(.headline)
                                                if let s = v.summary, !s.isEmpty
                                                {
                                                    Text(s)
                                                        .font(.caption)
                                                        .foregroundColor(
                                                            .secondary
                                                        )
                                                }
                                            }
                                            .padding(.vertical, 6)
                                            .padding(.horizontal)
                                        }
                                ) {
                                    ForEach(chaptersByVolume[v.id] ?? []) {
                                        chapter in
                                        let isCurrent =
                                            (initialChapterId == chapter.id)
                                        if let onSelect = onSelect {
                                            Button(action: { onSelect(chapter) }
                                            ) {
                                                Text(chapter.title)
                                                    .foregroundColor(
                                                        isCurrent
                                                            ? .accentColor
                                                            : .primary
                                                    )
                                                    .fontWeight(
                                                        isCurrent
                                                            ? .semibold
                                                            : .regular
                                                    )
                                                    .padding(.horizontal)
                                                    .padding(.vertical, 8)
                                            }
                                            .id(chapter.id)
                                        } else {
                                            NavigationLink(
                                                destination: ReaderView(
                                                    chapter: chapter
                                                )
                                            ) {
                                                Text(chapter.title)
                                                    .foregroundColor(
                                                        isCurrent
                                                            ? .accentColor
                                                            : .primary
                                                    )
                                                    .fontWeight(
                                                        isCurrent
                                                            ? .semibold
                                                            : .regular
                                                    )
                                                    .padding(.horizontal)
                                                    .padding(.vertical, 8)
                                            }
                                            .id(chapter.id)
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else {
                    List(filteredChapters) { chapter in
                        let isCurrent = (initialChapterId == chapter.id)
                        if let onSelect = onSelect {
                            Button(action: { onSelect(chapter) }) {
                                Text(chapter.title)
                                    .foregroundColor(
                                        isCurrent ? .accentColor : .primary
                                    )
                                    .fontWeight(
                                        isCurrent ? .semibold : .regular
                                    )
                            }
                            .id(chapter.id)
                        } else {
                            NavigationLink(
                                destination: ReaderView(chapter: chapter)
                            ) {
                                Text(chapter.title)
                                    .foregroundColor(
                                        isCurrent ? .accentColor : .primary
                                    )
                                    .fontWeight(
                                        isCurrent ? .semibold : .regular
                                    )
                            }
                            .id(chapter.id)
                        }
                    }
                }
            }
            .searchable(text: $searchText)
            .navigationTitle(book.title)
            .onAppear {
                loadData()
                attemptAutoScroll(proxy)
            }
            .onChange(of: chapters) { _, _ in
                attemptAutoScroll(proxy)
            }
        }
    }

    private var filteredChapters: [Chapter] {
        if searchText.isEmpty { return chapters }
        return chapters.filter { $0.title.contains(searchText) }
    }

    private func loadData() {
        guard let dbQueue = DatabaseManager.shared.dbQueue else { return }
        try? dbQueue.read { db in
            // 加载卷信息
            volumes = try Volume.filter(Column("bookid") == book.id)
                .order(Column("id"))
                .fetchAll(db)

            // 加载该书所有章节
            chapters = try Chapter.filter(Column("bookid") == book.id)
                .order(Column("id"))
                .fetchAll(db)

            // 章节按卷分组
            var grouped: [Int: [Chapter]] = [:]
            for ch in chapters {
                grouped[ch.volumeid, default: []].append(ch)
            }
            chaptersByVolume = grouped
        }
    }

    private func attemptAutoScroll(_ proxy: ScrollViewProxy) {
        // 仅在非搜索模式下自动滚动，避免影响搜索结果列表
        guard searchText.isEmpty else { return }
        guard !didAutoScroll, let targetId = initialChapterId else { return }
        guard let idx = chapters.firstIndex(where: { $0.id == targetId }) else {
            return
        }

        // 计算合适的定位：当前章的前 5 章置顶；如果不足 5 章，则置顶第 1 章
        // 如果是最后一章，则将其显示在底部
        let isLastChapter = (idx == chapters.count - 1)
        let scrollTargetId: Int
        let anchor: UnitPoint
        if isLastChapter {
            scrollTargetId = targetId
            anchor = .bottom
        } else {
            let adjustedIndex = max(idx - 5, 0)
            scrollTargetId = chapters[adjustedIndex].id
            anchor = .top
        }

        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(scrollTargetId, anchor: anchor)
            }
            didAutoScroll = true
        }
    }
}
