import Combine
// 在现有设置视图中增加一个“调试日志”开关（使用 AppStorage 持久化）
import SwiftUI

struct ReaderSettingsView: View {
    @Binding var fontSize: CGFloat
    @Binding var lineSpacing: CGFloat
    @Binding var paragraphSpacing: CGFloat
    @Binding var bgColor: Color
    @Binding var textColor: Color

    private enum ThemeOption: String, CaseIterable, Identifiable {
        case light = "浅色"
        case dark = "深色"
        var id: String { rawValue }
    }

    @State private var selectedTheme: ThemeOption = .light

    var body: some View {
        NavigationView {
            Form {
                // 字体大小设置
                Section(header: Text("字体大小")) {
                    HStack {
                        Text("当前大小: \(Int(fontSize))")
                        Spacer()
                        Button("-") { updateFontSize(increment: -2) }
                            .buttonStyle(.bordered)
                        Button("+") { updateFontSize(increment: 2) }
                            .buttonStyle(.bordered)
                    }
                }

                // 行间距设置
                Section(header: Text("行间距")) {
                    HStack {
                        Text("当前间距: \(Int(lineSpacing))")
                        Spacer()
                        Button("-") { updateLineSpacing(increment: -2) }
                            .buttonStyle(.bordered)
                        Button("+") { updateLineSpacing(increment: 2) }
                            .buttonStyle(.bordered)
                    }
                }

                // 段间距设置
                Section(header: Text("段间距")) {
                    HStack {
                        Text("当前间距: \(Int(paragraphSpacing))")
                        Spacer()
                        Button("-") { updateParagraphSpacing(increment: -4) }
                            .buttonStyle(.bordered)
                        Button("+") { updateParagraphSpacing(increment: 4) }
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
                    VStack(alignment: .leading, spacing: paragraphSpacing) {
                        Text("这是预览文本")
                            .font(.system(size: fontSize))
                            .foregroundColor(textColor)
                            .lineSpacing(lineSpacing)

                        Text("您可以在这里看到字体大小、行间距和段间距的效果。")
                            .font(.system(size: fontSize))
                            .foregroundColor(textColor)
                            .lineSpacing(lineSpacing)
                    }
                    .padding()
                    .background(bgColor)
                    .cornerRadius(8)
                }

                // 调试
                Section(header: Text("调试")) {
                    Toggle(
                        isOn: Binding(
                            get: {
                                UserDefaults.standard.bool(
                                    forKey: "ReaderDebugLoggingEnabled"
                                )
                            },
                            set: {
                                UserDefaults.standard.set(
                                    $0,
                                    forKey: "ReaderDebugLoggingEnabled"
                                )
                            }
                        )
                    ) {
                        Text("启用阅读调试日志")
                    }
                }
            }
            .navigationTitle("阅读设置")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            selectedTheme = inferTheme()
        }
        .onChange(of: selectedTheme) { _, newValue in
            switch newValue {
            case .light:
                updateTheme(background: "#FFFFFF", text: "#000000")
            case .dark:
                updateTheme(background: "#000000", text: "#FFFFFF")
            }
        }
    }

    // MARK: - Settings Update Methods
    private func updateFontSize(increment: CGFloat) {
        fontSize += increment
        UserDefaults.standard.set(fontSize, forKey: "ReaderFontSize")
        UserDefaults.standard.synchronize()
    }

    private func updateLineSpacing(increment: CGFloat) {
        lineSpacing += increment
        UserDefaults.standard.set(lineSpacing, forKey: "ReaderLineSpacing")
        UserDefaults.standard.synchronize()
    }

    private func updateParagraphSpacing(increment: CGFloat) {
        paragraphSpacing += increment
        UserDefaults.standard.set(
            paragraphSpacing,
            forKey: "ReaderParagraphSpacing"
        )
        UserDefaults.standard.synchronize()
    }

    private func updateTheme(background: String, text: String) {
        bgColor =
            Color(hex: background)
            ?? (background == "#FFFFFF" ? .white : .black)
        textColor = Color(hex: text) ?? (text == "#000000" ? .black : .white)

        UserDefaults.standard.set(background, forKey: "ReaderBackgroundColor")
        UserDefaults.standard.set(text, forKey: "ReaderTextColor")
        UserDefaults.standard.synchronize()
    }

    private func inferTheme() -> ThemeOption {
        if let bg = UserDefaults.standard.string(
            forKey: "ReaderBackgroundColor"
        ),
            let fg = UserDefaults.standard.string(forKey: "ReaderTextColor")
        {
            if bg.uppercased() == "#000000" && fg.uppercased() == "#FFFFFF" {
                return .dark
            }
        }
        return .light
    }
}

#Preview {
    ReaderSettingsView(
        fontSize: .constant(16),
        lineSpacing: .constant(8),
        paragraphSpacing: .constant(16),
        bgColor: .constant(.white),
        textColor: .constant(.black)
    )
}
