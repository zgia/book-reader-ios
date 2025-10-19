import SwiftUI
import UIKit

struct TextBookFormatView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Image(systemName: "info.circle")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)
                    .padding(.vertical, 20)

                Text(String(localized: "format.help.title"))
                    .font(.largeTitle.bold())
                    .padding(.bottom, 30)

                VStack(alignment: .leading, spacing: 30) {
                    formatRow(
                        systemName: "text.page",
                        label: String(localized: "format.help.format")
                    )
                    formatRow(
                        systemName: "character.book.closed",
                        label: String(localized: "format.help.book_name")
                    )
                    formatRow(
                        systemName: "person",
                        label: String(localized: "format.help.author")
                    )
                    formatRow(
                        systemName: "text.book.closed",
                        label: String(localized: "format.help.volume")
                    )
                    formatRow(
                        systemName: "book.pages",
                        label: String(localized: "format.help.chapter")
                    )
                    formatRow(
                        systemName: "book.and.wrench",
                        label: String(localized: "format.help.default")
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 30)

                Spacer()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "multiply")
                    }
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled)
            .interactiveDismissDisabled(false)
        }
    }

    @ViewBuilder
    private func formatRow(systemName: String, label: String)
        -> some View
    {
        Label {
            Text(label)
        } icon: {
            Image(systemName: systemName)
                .foregroundStyle(.blue)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }
}

#Preview("TextBookFormatView") {
    TextBookFormatView()
        .environmentObject(AppSettings())
}
