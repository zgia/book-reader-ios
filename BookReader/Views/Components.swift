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
                        Button(String(localized: "btn_cancel")) {
                            onCancel()
                        }
                        .frame(maxWidth: .infinity)
                        Button(String(localized: "btn_save")) {
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
                Section(String(localized: "bookinfo.basic_info")) {
                    infoRow(
                        systemName: "book",
                        label: String(localized: "bookinfo.name"),
                        value: book.title
                    )
                    infoRow(
                        systemName: "person",
                        label: String(localized: "bookinfo.author"),
                        value: book.author
                    )
                    if !book.category.isEmpty {
                        infoRow(
                            systemName: "tag",
                            label: String(localized: "bookinfo.category"),
                            value: book.category
                        )
                    }
                    infoRow(
                        systemName: "textformat.123",
                        label: String(localized: "bookinfo.wordcount"),
                        value: WordCountFormatter.string(from: book.wordcount)
                    )
                    infoRow(
                        systemName: book.isfinished == 1
                            ? "checkmark.seal" : "clock",
                        label: String(localized: "bookinfo.status"),
                        value: book.isfinished == 1
                            ? String(localized: "bookinfo.finished")
                            : String(localized: "bookinfo.status_ongoing")
                    )
                    infoRow(
                        systemName: "calendar.badge.clock",
                        label: String(localized: "bookinfo.last_updated_at"),
                        value: formatDate(book.updatedat)
                    )
                    if !book.latest.isEmpty {
                        infoRow(
                            systemName: "list.bullet",
                            label: String(
                                localized: "bookinfo.latest_chapter"
                            ),
                            value: book.latest
                        )
                    }
                }

                Section(String(localized: "bookinfo.reading")) {
                    infoRow(
                        systemName: "percent",
                        label: String(localized: "bookinfo.reading_percent"),
                        value: progressText
                    )
                }
            }
            .navigationTitle(String(localized: "book_info.title"))
            //.toolbar {
            //    ToolbarItem(placement: .topBarTrailing) {
            //        Button(String(localized: "btn_done")) { dismiss() }
            //    }
            //}
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .navigationBarTitleDisplayMode(.inline)
            .presentationBackgroundInteraction(.enabled)
            .interactiveDismissDisabled(false)
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

    private func formatDate(_ ts: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ts))
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
