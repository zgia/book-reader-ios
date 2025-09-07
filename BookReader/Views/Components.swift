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

struct TextFieldDialog: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let onCancel: () -> Void
    let onSave: () -> Void
    let topOffset: CGFloat = 120

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack {
                VStack(spacing: 16) {
                    Text(title)
                        .font(.headline)
                    TextField(placeholder, text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(10)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    HStack {
                        Button("取消") {
                            onCancel()
                        }
                        .frame(maxWidth: .infinity)
                        Button("保存") {
                            onSave()
                        }
                        .frame(maxWidth: .infinity)
                        .disabled(
                            text.trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty
                        )
                    }
                }
                .padding(20)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 40)
                .padding(.top, topOffset)

                Spacer()
            }
        }
    }
}
