import SwiftUI

final class ReadingSettings: ObservableObject {
    struct SavedColorPreset: Identifiable, Codable, Equatable {
        let id: UUID
        var name: String
        var backgroundHex: String
        var textHex: String

        init(
            id: UUID = UUID(),
            name: String,
            backgroundHex: String,
            textHex: String
        ) {
            self.id = id
            self.name = name
            self.backgroundHex = backgroundHex
            self.textHex = textHex
        }
    }
    @Published var fontSize: Double = 16
    @Published var lineSpacing: Double = 8
    @Published var paragraphSpacing: Double = 16
    @Published var backgroundHex: String = "#FFFFFF"
    @Published var textHex: String = "#000000"
    @Published var debugEnabled: Bool = false
    @Published var savedPresets: [SavedColorPreset] = []

    var backgroundColor: Color { Color(hex: backgroundHex) ?? .white }
    var textColor: Color { Color(hex: textHex) ?? .black }

    func applyPreset(_ preset: SavedColorPreset) {
        backgroundHex = preset.backgroundHex
        textHex = preset.textHex
    }

    func saveCurrentAsPreset(named name: String) {
        let newPreset = SavedColorPreset(
            name: name,
            backgroundHex: backgroundHex,
            textHex: textHex
        )
        // 去重：相同颜色组合仅保留一个，名称以最新为准
        savedPresets.removeAll {
            $0.backgroundHex == newPreset.backgroundHex
                && $0.textHex == newPreset.textHex
        }
        savedPresets.insert(newPreset, at: 0)
    }

    func deletePreset(_ preset: SavedColorPreset) {
        savedPresets.removeAll { $0.id == preset.id }
    }

    func renamePreset(_ preset: SavedColorPreset, newName: String) {
        guard let index = savedPresets.firstIndex(where: { $0.id == preset.id })
        else { return }
        savedPresets[index].name = newName
    }
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
    @AppStorage(DefaultsKeys.readerSavedColorPresets) private
        var storedPresetsJSON: String = "[]"

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
            .onChange(of: storedPresetsJSON) { _, _ in
                settings.savedPresets = decodePresets(from: storedPresetsJSON)
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
            .onChange(of: settings.savedPresets) { _, newValue in
                storedPresetsJSON = encodePresets(newValue)
            }
    }

    private func syncFromStorage() {
        settings.fontSize = storedFontSize
        settings.lineSpacing = storedLineSpacing
        settings.paragraphSpacing = storedParagraphSpacing
        settings.backgroundHex = storedBgHex
        settings.textHex = storedTextHex
        settings.debugEnabled = storedDebug
        settings.savedPresets = decodePresets(from: storedPresetsJSON)
    }

    private func decodePresets(from json: String) -> [ReadingSettings
        .SavedColorPreset]
    {
        guard let data = json.data(using: .utf8) else { return [] }
        do {
            return try JSONDecoder().decode(
                [ReadingSettings.SavedColorPreset].self,
                from: data
            )
        } catch {
            return []
        }
    }

    private func encodePresets(_ presets: [ReadingSettings.SavedColorPreset])
        -> String
    {
        do {
            let data = try JSONEncoder().encode(presets)
            return String(data: data, encoding: .utf8) ?? "[]"
        } catch {
            return "[]"
        }
    }
}
