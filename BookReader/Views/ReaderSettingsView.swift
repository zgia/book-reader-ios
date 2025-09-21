import SwiftUI
import UIKit

struct ReaderSettingsView: View {
    @EnvironmentObject private var reading: ReadingSettings

    private struct ColorPreset: Identifiable {
        let id = UUID()
        let name: String
        let backgroundHex: String
        let textHex: String
    }

    private let presets: [ColorPreset] = [
        ColorPreset(
            name: String(localized: "setting.color_light"),
            backgroundHex: "#FFFFFF",
            textHex: "#000000"
        ),
        ColorPreset(
            name: String(localized: "setting.color_dark"),
            backgroundHex: "#000000",
            textHex: "#FFFFFF"
        ),
        ColorPreset(
            name: String(localized: "setting.color_soft_yellow"),
            backgroundHex: "#F5ECD9",
            textHex: "#5B4636"
        ),
        ColorPreset(
            name: String(localized: "setting.color_warm_paper"),
            backgroundHex: "#FAF3E0",
            textHex: "#3A3A3A"
        ),
        ColorPreset(
            name: String(localized: "setting.color_green"),
            backgroundHex: "#CCE8CF",
            textHex: "#2B3D2F"
        ),
        ColorPreset(
            name: String(localized: "setting.color_deep_grey"),
            backgroundHex: "#121212",
            textHex: "#EAEAEA"
        ),
    ]

    var body: some View {
        NavigationStack {
            Form {
                // 字体大小设置
                Section(header: Text(String(localized: "setting.font_size"))) {
                    HStack {
                        Text(
                            String(
                                format: String(
                                    localized: "setting.current_font_size"
                                ),
                                Int(reading.fontSize)
                            )
                        )
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
                Section(header: Text(String(localized: "setting.line_spacing")))
                {
                    HStack {
                        Text(
                            String(
                                format: String(
                                    localized: "setting.current_line_spacing"
                                ),
                                Int(reading.lineSpacing)
                            )
                        )
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
                Section(
                    header: Text(String(localized: "setting.paragraph_spacing"))
                ) {
                    HStack {
                        Text(
                            String(
                                format: String(
                                    localized:
                                        "setting.current_paragraph_spacing"
                                ),
                                Int(reading.paragraphSpacing)
                            )
                        )
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

                // 预设配色
                Section(
                    header: Text(String(localized: "setting.color_presets"))
                ) {
                    let columns = [
                        GridItem(.flexible()), GridItem(.flexible()),
                    ]
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(presets) { preset in
                            Button {
                                reading.backgroundHex = preset.backgroundHex
                                reading.textHex = preset.textHex
                            } label: {
                                HStack {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(
                                                Color(hex: preset.backgroundHex)
                                                    ?? .white
                                            )
                                            .frame(width: 44, height: 28)
                                            .overlay(
                                                Text("Aa")
                                                    .font(.headline)
                                                    .foregroundColor(
                                                        Color(
                                                            hex: preset.textHex
                                                        ) ?? .black
                                                    )
                                            )
                                    }
                                    Text(preset.name)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(
                                            Color(
                                                uiColor:
                                                    .secondarySystemBackground
                                            )
                                        )
                                )
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                // 自定义颜色
                Section(
                    header: Text(String(localized: "setting.color_customize"))
                ) {
                    ColorPicker(
                        String(localized: "setting.color_font"),
                        selection: Binding(
                            get: { Color(hex: reading.textHex) ?? .black },
                            set: { newColor in
                                reading.textHex = hexString(from: newColor)
                            }
                        ),
                        supportsOpacity: false
                    )

                    ColorPicker(
                        String(localized: "setting.color_background"),
                        selection: Binding(
                            get: {
                                Color(hex: reading.backgroundHex) ?? .white
                            },
                            set: { newColor in
                                reading.backgroundHex = hexString(
                                    from: newColor
                                )
                            }
                        ),
                        supportsOpacity: false
                    )
                }

                // 预览区域
                Section(header: Text(String(localized: "setting.preview"))) {
                    VStack(
                        alignment: .leading,
                        spacing: reading.paragraphSpacing
                    ) {
                        Text(String(localized: "setting.preview_text_1"))
                            .font(.system(size: reading.fontSize))
                            .foregroundColor(reading.textColor)
                            .lineSpacing(reading.lineSpacing)

                        Text(String(localized: "setting.preview_text_2"))
                            .font(.system(size: reading.fontSize))
                            .foregroundColor(reading.textColor)
                            .lineSpacing(reading.lineSpacing)
                    }
                    .padding()
                    .background(reading.backgroundColor)
                    .cornerRadius(8)
                }

                // 调试
                Section(header: Text(String(localized: "setting.debug"))) {
                    Toggle(
                        String(localized: "setting.debug_log_enabled"),
                        isOn: $reading.debugEnabled
                    )
                }
            }
            .navigationTitle(String(localized: "setting.reading_setting"))
            .presentationDragIndicator(.visible)
            .navigationBarTitleDisplayMode(.inline)
            .presentationBackgroundInteraction(.enabled)
            .interactiveDismissDisabled(false)
        }
    }

    private func hexString(from color: Color) -> String {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        if uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            let r = Int(round(red * 255))
            let g = Int(round(green * 255))
            let b = Int(round(blue * 255))
            return String(format: "#%02X%02X%02X", r, g, b)
        }
        // 回退：直接返回当前存储，避免写入无效值
        return reading.textHex
    }
}

#Preview {
    ReaderSettingsView()
        .environmentObject(ReadingSettings())
}
