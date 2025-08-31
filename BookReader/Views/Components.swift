import SwiftUI

struct ReaderToolbar: View {
    @EnvironmentObject var settings: ThemeSettings
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button("关闭", action: onClose)
            Divider().frame(height: 20)
            Stepper(
                "字号 \(Int(settings.fontSize))",
                value: $settings.fontSize,
                in: 14...28,
                step: 2
            )
            Stepper(
                "行距 \(Int(settings.lineSpacing))",
                value: $settings.lineSpacing,
                in: 0...12,
                step: 2
            )
            Menu("主题") {
                Button("明亮") { settings.theme = "light" }
                Button("护眼") { settings.theme = "sepia" }
                Button("深色") { settings.theme = "dark" }
            }
            Menu("模式：\(settings.mode.title)") {
                Button("滚动") { settings.setMode(.scroll) }
                Button("翻页") { settings.setMode(.page) }
            }
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
    }
}
