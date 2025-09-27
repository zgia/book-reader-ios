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

    // ProgressStore
    static let readingProgress = "reading_progress_v1"
}
