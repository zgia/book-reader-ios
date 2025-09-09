import SwiftUI

struct ReaderSettingsView: View {
    @EnvironmentObject private var reading: ReadingSettings

    private enum ThemeOption: String, CaseIterable, Identifiable {
        case light = "浅色"
        case dark = "深色"
        var id: String { rawValue }
    }

    @State private var selectedTheme: ThemeOption = .light

    var body: some View {
        NavigationStack {
            Form {
                // 字体大小设置
                Section(header: Text("字体大小")) {
                    HStack {
                        Text("当前大小: \(Int(reading.fontSize))")
                        Spacer()
                        Button("-") {
                            reading.fontSize = max(8, reading.fontSize - 2)
                        }
                        .buttonStyle(.bordered)
                        Button("+") {
                            reading.fontSize = min(72, reading.fontSize + 2)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                // 行间距设置
                Section(header: Text("行间距")) {
                    HStack {
                        Text("当前间距: \(Int(reading.lineSpacing))")
                        Spacer()
                        Button("-") {
                            reading.lineSpacing = max(
                                0,
                                reading.lineSpacing - 2
                            )
                        }
                        .buttonStyle(.bordered)
                        Button("+") {
                            reading.lineSpacing = min(
                                48,
                                reading.lineSpacing + 2
                            )
                        }
                        .buttonStyle(.bordered)
                    }
                }

                // 段间距设置
                Section(header: Text("段间距")) {
                    HStack {
                        Text("当前间距: \(Int(reading.paragraphSpacing))")
                        Spacer()
                        Button("-") {
                            reading.paragraphSpacing = max(
                                0,
                                reading.paragraphSpacing - 4
                            )
                        }
                        .buttonStyle(.bordered)
                        Button("+") {
                            reading.paragraphSpacing = min(
                                96,
                                reading.paragraphSpacing + 4
                            )
                        }
                        .buttonStyle(.bordered)
                    }
                }

                // 主题设置
                Section(header: Text("主题")) {
                    Picker("主题", selection: $selectedTheme) {
                        ForEach(ThemeOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // 预览区域
                Section(header: Text("预览")) {
                    VStack(
                        alignment: .leading,
                        spacing: reading.paragraphSpacing
                    ) {
                        Text("这是预览文本")
                            .font(.system(size: reading.fontSize))
                            .foregroundColor(reading.textColor)
                            .lineSpacing(reading.lineSpacing)

                        Text("您可以在这里看到字体大小、行间距和段间距的效果。")
                            .font(.system(size: reading.fontSize))
                            .foregroundColor(reading.textColor)
                            .lineSpacing(reading.lineSpacing)
                    }
                    .padding()
                    .background(reading.backgroundColor)
                    .cornerRadius(8)
                }

                // 调试
                Section(header: Text("调试")) {
                    Toggle("启用阅读调试日志", isOn: $reading.debugEnabled)
                }
            }
            .navigationTitle("阅读设置")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { selectedTheme = inferTheme() }
        .onChange(of: selectedTheme) { _, newValue in
            switch newValue {
            case .light:
                updateTheme(background: "#FFFFFF", text: "#000000")
            case .dark:
                updateTheme(background: "#000000", text: "#FFFFFF")
            }
        }
    }

    private func updateTheme(background: String, text: String) {
        reading.backgroundHex = background
        reading.textHex = text
    }

    private func inferTheme() -> ThemeOption {
        let bg = reading.backgroundHex
        let fg = reading.textHex
        if bg.uppercased() == "#000000" && fg.uppercased() == "#FFFFFF" {
            return .dark
        }
        return .light
    }
}

#Preview {
    ReaderSettingsView()
        .environmentObject(ReadingSettings())
}
