import SwiftUI

final class ReadingSettings: ObservableObject {
    @Published var fontSize: Double = 16
    @Published var lineSpacing: Double = 8
    @Published var paragraphSpacing: Double = 16
    @Published var backgroundHex: String = "#FFFFFF"
    @Published var textHex: String = "#000000"
    @Published var debugEnabled: Bool = false

    var backgroundColor: Color { Color(hex: backgroundHex) ?? .white }
    var textColor: Color { Color(hex: textHex) ?? .black }
}

struct ReadingSettingsProvider<Content: View>: View {
    // Backing storage via @AppStorage
    @AppStorage(DefaultsKeys.readerFontSize) private var storedFontSize:
        Double = 16
    @AppStorage(DefaultsKeys.readerLineSpacing) private var storedLineSpacing:
        Double = 8
    @AppStorage(DefaultsKeys.readerParagraphSpacing) private
        var storedParagraphSpacing: Double = 16
    @AppStorage(DefaultsKeys.readerBackgroundColor) private var storedBgHex:
        String = "#FFFFFF"
    @AppStorage(DefaultsKeys.readerTextColor) private var storedTextHex:
        String = "#000000"
    @AppStorage(DefaultsKeys.readerDebugLoggingEnabled) private var storedDebug:
        Bool = false

    @StateObject private var settings = ReadingSettings()
    let content: () -> Content

    var body: some View {
        content()
            .environmentObject(settings)
            .onAppear { syncFromStorage() }
            .onChange(of: storedFontSize) { _, _ in
                settings.fontSize = storedFontSize
            }
            .onChange(of: storedLineSpacing) { _, _ in
                settings.lineSpacing = storedLineSpacing
            }
            .onChange(of: storedParagraphSpacing) { _, _ in
                settings.paragraphSpacing = storedParagraphSpacing
            }
            .onChange(of: storedBgHex) { _, _ in
                settings.backgroundHex = storedBgHex
            }
            .onChange(of: storedTextHex) { _, _ in
                settings.textHex = storedTextHex
            }
            .onChange(of: storedDebug) { _, _ in
                settings.debugEnabled = storedDebug
            }
            .onChange(of: settings.fontSize) { _, newValue in
                storedFontSize = newValue
            }
            .onChange(of: settings.lineSpacing) { _, newValue in
                storedLineSpacing = newValue
            }
            .onChange(of: settings.paragraphSpacing) { _, newValue in
                storedParagraphSpacing = newValue
            }
            .onChange(of: settings.backgroundHex) { _, newValue in
                storedBgHex = newValue
            }
            .onChange(of: settings.textHex) { _, newValue in
                storedTextHex = newValue
            }
            .onChange(of: settings.debugEnabled) { _, newValue in
                storedDebug = newValue
            }
    }

    private func syncFromStorage() {
        settings.fontSize = storedFontSize
        settings.lineSpacing = storedLineSpacing
        settings.paragraphSpacing = storedParagraphSpacing
        settings.backgroundHex = storedBgHex
        settings.textHex = storedTextHex
        settings.debugEnabled = storedDebug
    }
}
