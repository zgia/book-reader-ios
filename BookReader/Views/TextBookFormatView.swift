import SwiftUI
import UIKit

struct TextBookFormatView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label {
                        Text(String(localized: "format.help.format"))
                    } icon: {
                        Image(systemName: "text.page")
                    }
                    Label {
                        Text(String(localized: "format.help.book_name"))
                    } icon: {
                        Image(systemName: "character.book.closed")
                    }
                    Label {
                        Text(String(localized: "format.help.author"))
                    } icon: {
                        Image(systemName: "person")
                    }
                    Label {
                        Text(String(localized: "format.help.volume"))
                    } icon: {
                        Image(systemName: "text.book.closed")
                    }
                    Label {
                        Text(String(localized: "format.help.chapter"))
                    } icon: {
                        Image(systemName: "book.pages")
                    }
                    Label {
                        Text(String(localized: "format.help.default"))
                    } icon: {
                        Image(systemName: "book.and.wrench")
                    }

                }
            }
            .navigationTitle(String(localized: "format.help.title"))
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .navigationBarTitleDisplayMode(.inline)
            .presentationBackgroundInteraction(.enabled)
            .interactiveDismissDisabled(false)
        }
    }
}
