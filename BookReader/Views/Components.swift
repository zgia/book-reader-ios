import SwiftUI

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

// 书籍信息底部弹窗（支持中/大全高拉动）
struct BookInfoSheetView: View {
    let book: Book
    let progressText: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("基本信息") {
                    infoRow(systemName: "book", label: "书名", value: book.title)
                    infoRow(
                        systemName: "person",
                        label: "作者",
                        value: book.author
                    )
                    if !book.category.isEmpty {
                        infoRow(
                            systemName: "tag",
                            label: "分类",
                            value: book.category
                        )
                    }
                    infoRow(
                        systemName: "textformat.123",
                        label: "总字数",
                        value: formatWordCount(book.wordcount)
                    )
                    infoRow(
                        systemName: book.isfinished == 1
                            ? "checkmark.seal" : "clock",
                        label: "状态",
                        value: book.isfinished == 1 ? "完本" : "连载"
                    )
                    infoRow(
                        systemName: "calendar.badge.clock",
                        label: "最近更新",
                        value: formatDate(book.updatedat)
                    )
                }

                Section("阅读") {
                    infoRow(
                        systemName: "percent",
                        label: "进度",
                        value: progressText
                    )
                    if !book.latest.isEmpty {
                        infoRow(
                            systemName: "list.bullet",
                            label: "最新章节",
                            value: book.latest
                        )
                    }
                }
            }
            .navigationTitle("书籍信息")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func infoRow(systemName: String, label: String, value: String)
        -> some View
    {
        HStack {
            Label {
                Text(label)
            } icon: {
                Image(systemName: systemName)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 16)
            Text(value)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }

    private func formatWordCount(_ count: Int) -> String {
        if count >= 10000 {
            let n = Double(count) / 10000.0
            return String(format: "%.1f万字", n)
        } else {
            return "\(count)字"
        }
    }

    private func formatDate(_ ts: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ts))
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
