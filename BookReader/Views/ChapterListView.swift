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
        guard !didAutoScroll, let targetId = initialChapterId else { return }
        let exists = chapters.contains(where: { $0.id == targetId })
        guard exists else { return }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(targetId, anchor: .top)
            }
            didAutoScroll = true
        }
    }
}
