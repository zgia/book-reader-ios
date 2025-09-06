import Foundation
import GRDB

struct Category: Codable, FetchableRecord, PersistableRecord, Identifiable,
    Equatable
{
    var id: Int
    var title: String  // 分类标题
}

struct BookAuthor: Codable, FetchableRecord, PersistableRecord, Identifiable,
    Equatable
{
    var id: Int
    var title: String  // 作者名称
}

struct Book: Codable, FetchableRecord, PersistableRecord, Identifiable,
    Equatable
{
    var id: Int
    var category: String  // 分类
    var title: String  // 书名
    var author: String  // 作者
    var latest: String  // 本书最后一章的标题
    var wordcount: Int  // 本书总字数
    var isfinished: Int  // 0: 未完本，1: 完本
    var updatedat: Int  // 时间戳，记录图书的最后更新时间
}

struct Volume: Codable, FetchableRecord, PersistableRecord, Identifiable,
    Equatable
{
    var id: Int
    var bookid: Int
    var title: String  // 卷名
    var summary: String?  // 卷简介（可空）
}

struct Chapter: Codable, FetchableRecord, PersistableRecord, Identifiable,
    Equatable, Hashable
{
    var id: Int
    var bookid: Int
    var volumeid: Int
    var title: String  // 章节标题
}

struct Content: Codable, FetchableRecord, PersistableRecord, Identifiable,
    Equatable
{
    // 表结构里主键是 chapterid，这里做 Identifiable 适配
    var id: Int { chapterid }
    var chapterid: Int
    var txt: String?  // 章节内容
}

// 列表展示的合成模型
struct BookRow: Identifiable, Equatable {
    var id: Int { book.id }
    let book: Book
    let categoryTitle: String
    let lastProgress: ReadingProgress?  // 可为空
}
