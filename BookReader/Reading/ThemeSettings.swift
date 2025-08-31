import SwiftUI

enum ReadingMode: String, CaseIterable, Identifiable {
    case scroll, page
    var id: String { rawValue }
    var title: String { self == .scroll ? "滚动" : "翻页" }
}

final class ThemeSettings: ObservableObject {
    @AppStorage("fontSize") var fontSize: Double = 18
    @AppStorage("lineSpacing") var lineSpacing: Double = 6
    @AppStorage("theme") var theme: String = "light"  // light / sepia / dark
    @AppStorage("readingMode") var readingModeRaw: String = ReadingMode.scroll
        .rawValue

    var mode: ReadingMode { ReadingMode(rawValue: readingModeRaw) ?? .scroll }
    func setMode(_ m: ReadingMode) {
        readingModeRaw = m.rawValue
        objectWillChange.send()
    }

    var foreground: Color { theme == "dark" ? .white : .primary }
    var background: Color {
        switch theme {
        case "dark": return .black
        case "sepia": return Color(red: 0.98, green: 0.95, blue: 0.89)
        default: return .white
        }
    }
}
