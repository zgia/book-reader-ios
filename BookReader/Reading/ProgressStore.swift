import Foundation

struct ReadingProgress: Codable, Equatable {
    let bookId: Int
    let chapterId: Int
    let percent: Double  // 0~1，滚动或翻页百分比
    let pageIndex: Int?  // 可选的页索引（优先用于恢复定位）
}

final class ProgressStore: ObservableObject {
    private let key = DefaultsKeys.readingProgress
    @Published private(set) var map: [Int: ReadingProgress] = [:]  // bookId -> progress

    init() {
        load()
    }

    // 更新某本书的进度
    func update(_ p: ReadingProgress) {
        map[p.bookId] = p
        save()
    }

    // 获取某本书的进度
    func lastProgress(forBook id: Int) -> ReadingProgress? {
        map[id]
    }

    // 一次性获取所有进度（避免 N+1 查询）
    func allProgress() -> [Int: ReadingProgress] {
        map
    }

    // MARK: - 持久化
    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
            let m = try? JSONDecoder().decode(
                [Int: ReadingProgress].self,
                from: data
            )
        {
            map = m
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    // 清除某本书的阅读进度
    func clear(forBook id: Int) {
        map.removeValue(forKey: id)
        save()
    }
}
