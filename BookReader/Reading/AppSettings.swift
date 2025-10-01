import SwiftUI

enum AppAppearanceOption: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return String(localized: "appearance.system")
        case .light: return String(localized: "appearance.light")
        case .dark: return String(localized: "appearance.dark")
        }
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @AppStorage(DefaultsKeys.appAppearanceOption) private
        var storedOption: String = AppAppearanceOption.system.rawValue

    @AppStorage(DefaultsKeys.hideHiddenCategoriesInManagement) private
        var storedHideHiddenCategoriesInManagement: Bool = false

    @AppStorage(DefaultsKeys.debugEnabled) private
        var storedDebugEnabled: Bool = false

    var option: AppAppearanceOption {
        AppAppearanceOption(rawValue: storedOption) ?? .system
    }

    func setOption(_ newValue: AppAppearanceOption) {
        storedOption = newValue.rawValue
        objectWillChange.send()
    }

    /// 获取分类管理中是否隐藏“隐藏的分类”的设置
    func isHidingHiddenCategoriesInManagement() -> Bool {
        storedHideHiddenCategoriesInManagement
    }

    /// 设置分类管理中是否隐藏“隐藏的分类”
    func setHidingHiddenCategoriesInManagement(_ newValue: Bool) {
        storedHideHiddenCategoriesInManagement = newValue
        objectWillChange.send()
    }

    /// 获取调试是否开启
    func isDebugEnabled() -> Bool {
        storedDebugEnabled
    }

    /// 设置调试是否开启
    func setDebugEnabled(_ newValue: Bool) {
        storedDebugEnabled = newValue
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
