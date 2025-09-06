import SwiftUI
import UniformTypeIdentifiers

struct AppSettingsView: View {
    @EnvironmentObject private var appAppearance: AppAppearanceSettings
    @EnvironmentObject private var dbManager: DatabaseManager

    @State private var showPreviewButton: Bool = false
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
                    if showPreviewButton {
                        Button(action: onPreviewButtonTapped) {
                            Text("预览解析（不入库）")
                        }
                        .fileImporter(
                            isPresented: $showingPreviewImporter,
                            allowedContentTypes: [.plainText],
                            allowsMultipleSelection: false
                        ) { handlePreviewFileImport($0) }
                    }

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

                    VStack(alignment: .leading, spacing: 6) {
                        Text("TXT 格式说明：").font(.footnote).bold()
                        Text("· 书名：支持“书名：xxx”或仅“《xxx》”；若未识别则使用文件名（去扩展名）。")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Text("· 作者：建议以“作者：xxx”独立一行。")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Text("· 卷名：行首以“第X卷 卷名”开头（支持中文或阿拉伯数字），行首请勿留空格。")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Text("· 章节：行首以“第X章 章节名”开头（支持中文或阿拉伯数字），行首请勿留空格。")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Text("· 章节前的内容会被忽略；未出现卷时会自动创建“正文”卷。")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }

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

#Preview("设置") {
    AppSettingsView()
        .environmentObject(AppAppearanceSettings())
        .environmentObject(DatabaseManager.shared)
}
