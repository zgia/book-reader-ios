import SwiftUI

enum AppAppearanceOption: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}

final class AppAppearanceSettings: ObservableObject {
    @AppStorage("AppAppearanceOption") private var storedOption: String =
        AppAppearanceOption.system.rawValue

    var option: AppAppearanceOption {
        AppAppearanceOption(rawValue: storedOption) ?? .system
    }

    func setOption(_ newValue: AppAppearanceOption) {
        storedOption = newValue.rawValue
        objectWillChange.send()
    }

    var preferredColorScheme: ColorScheme? {
        switch option {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
