import Foundation

enum DefaultsKeys {
    // Reader preferences
    static let readerFontSize = "ReaderFontSize"
    static let readerLineSpacing = "ReaderLineSpacing"
    static let readerParagraphSpacing = "ReaderParagraphSpacing"
    static let readerBackgroundColor = "ReaderBackgroundColor"
    static let readerTextColor = "ReaderTextColor"
    static let readerDebugLoggingEnabled = "ReaderDebugLoggingEnabled"
    static let readerSavedColorPresets = "ReaderSavedColorPresetsJSON"

    // App
    static let securityOverlayEnabled = "SecurityOverlayEnabled"
    static let hideHiddenCategoriesInManagement =
        "HideHiddenCategoriesInManagement"
    static let appAppearanceOption = "AppAppearanceOption"
    static let debugEnabled = "DebugEnabled"

    // ProgressStore
    static let readingProgress = "ReadingProgressV1"
}
