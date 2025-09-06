import SwiftUI
import UniformTypeIdentifiers

struct AppSettingsView: View {
    @EnvironmentObject private var appAppearance: AppAppearanceSettings
    @EnvironmentObject private var dbManager: DatabaseManager

    @State private var showingPreviewImporter: Bool = false
    @State private var showingWriteImporter: Bool = false
    @State private var importInProgress: Bool = false
    @State private var importMessage: String?

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

                Section(header: Text("数据")) {
                    //                    Button(action: onPreviewButtonTapped) {
                    //                        Text("预览解析（不入库）")
                    //                    }
                    //                    .fileImporter(
                    //                        isPresented: $showingPreviewImporter,
                    //                        allowedContentTypes: [.plainText],
                    //                        allowsMultipleSelection: false
                    //                    ) { handlePreviewFileImport($0) }

                    Button(action: onImportButtonTapped) {
                        HStack {
                            if importInProgress {
                                ProgressView().scaleEffect(0.8)
                            }
                            Text(importInProgress ? "正在导入…" : "导入小说")
                        }
                    }
                    .disabled(importInProgress)
                    .fileImporter(
                        isPresented: $showingWriteImporter,
                        allowedContentTypes: [.plainText],
                        allowsMultipleSelection: false
                    ) { handleWriteFileImport($0) }

                    if let msg = importMessage {
                        Text(msg).font(.footnote).foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("设置")
        }
    }

    private func onPreviewButtonTapped() {
        showingPreviewImporter = true
    }

    private func onImportButtonTapped() {
        showingWriteImporter = true
    }

    private func handlePreviewFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let importer = TxtBookImporter(dbManager: dbManager)
                    try importer.importTxtPreview(at: url)
                } catch {
                    DispatchQueue.main.async {
                        importMessage = "预览失败：\(error.localizedDescription)"
                    }
                }
            }
        case .failure(let error):
            importMessage = "选择文件失败：\(error.localizedDescription)"
        }
    }

    private func handleWriteFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            importInProgress = true
            importMessage = nil
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let importer = TxtBookImporter(dbManager: dbManager)
                    try importer.importTxt(at: url)
                    DispatchQueue.main.async {
                        importInProgress = false
                        importMessage = "导入完成"
                    }
                } catch {
                    DispatchQueue.main.async {
                        importInProgress = false
                        importMessage = "导入失败：\(error.localizedDescription)"
                    }
                }
            }
        case .failure(let error):
            importMessage = "选择文件失败：\(error.localizedDescription)"
        }
    }
}
