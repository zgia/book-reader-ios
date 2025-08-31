import SwiftUI

struct AppSettingsView: View {
    @EnvironmentObject private var appAppearance: AppAppearanceSettings

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("外观")) {
                    Picker(
                        "应用外观",
                        selection: Binding(
                            get: { appAppearance.option },
                            set: { appAppearance.setOption($0) }
                        )
                    ) {
                        ForEach(AppAppearanceOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("设置")
        }
    }
}
