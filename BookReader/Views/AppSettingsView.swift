import SwiftUI
import UniformTypeIdentifiers

struct AppSettingsView: View {
    @EnvironmentObject private var appAppearance: AppAppearanceSettings
    @EnvironmentObject private var dbManager: DatabaseManager
    @AppStorage(DefaultsKeys.securityOverlayEnabled) private
        var securityOverlayEnabled: Bool = true

    @State private var showPreviewButton: Bool = false
    @State private var showingPreviewImporter: Bool = false
    @State private var showingWriteImporter: Bool = false
    @State private var importInProgress: Bool = false
    @State private var importMessage: String?
    @State private var compressionMessage: String?
    @State private var showingCompactConfirm: Bool = false
    @State private var statsText: String = ""
    @State private var showingFormatHelp: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                // 外观
                appAppearanceView()

                // 隐私与安全
                securityView()

                // 导入小说
                bookImporterView()

                // 新的“数据库维护”分区
                databaseMaintainerView()
            }
            .navigationTitle("设置")
            .onAppear { refreshStatsAsync() }
            .sheet(isPresented: $showingFormatHelp) {
                textBookFormatHelpView()
            }
        }
    }

    @ViewBuilder
    private func textBookFormatHelpView() -> some View {
        NavigationStack {
            List {
                Section {
                    Label {
                        Text("格式：仅支持文本格式：*.txt。")
                    } icon: {
                        Image(systemName: "text.page")
                    }
                    Label {
                        Text("书名：支持“书名：xxx”或仅“《xxx》”；若未识别则使用文件名（去扩展名）。")
                    } icon: {
                        Image(systemName: "character.book.closed")
                    }
                    Label {
                        Text("作者：建议以“作者：xxx”独立一行。")
                    } icon: {
                        Image(systemName: "person")
                    }
                    Label {
                        Text("卷名：行首以“第X卷 卷名”开头（支持中文或阿拉伯数字），行首请勿留空格。")
                    } icon: {
                        Image(systemName: "text.book.closed")
                    }
                    Label {
                        Text("章节：行首以“第X章 章节名”开头（支持中文或阿拉伯数字），行首请勿留空格。")
                    } icon: {
                        Image(systemName: "book.pages")
                    }
                    Label {
                        Text("默认：章节前的内容会被忽略；未出现卷时会自动创建“正文”卷。")
                    } icon: {
                        Image(systemName: "book.and.wrench")
                    }

                }
            }
            .navigationTitle("小说格式说明")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { showingFormatHelp = false }
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled)
            .interactiveDismissDisabled(false)
        }
    }

    @ViewBuilder
    private func databaseMaintainerView() -> some View {
        Section(
            header: Text("数据库维护"),
            footer: VStack(alignment: .leading, spacing: 6) {
                Text("删除图书时，可能不会自动释放空间，需要手动释放。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        ) {
            HStack {
                Text("数据库统计")
                Spacer()
                Button("刷新") { refreshStats() }
                    .font(.footnote)
            }
            if !statsText.isEmpty {
                Text(statsText)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Button(action: { showingCompactConfirm = true }) {
                HStack {
                    if dbManager.isCompacting {
                        ProgressView().scaleEffect(0.8)
                    }
                    Text(
                        dbManager.isCompacting
                            ? "正在全量压缩…" : "释放空间（全量压缩）"
                    )
                }
            }
            .disabled(dbManager.isCompacting)
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .alert("确认执行全量压缩？", isPresented: $showingCompactConfirm) {
                Button("取消", role: .cancel) {}
                Button("确定", role: .destructive) {
                    onCompactButtonTapped()
                }
            } message: {
                Text("该操作将执行 VACUUM，可能耗时较长，请在空闲时进行。")
            }
            if let cmsg = compressionMessage {
                Text(cmsg).font(.footnote).foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func bookImporterView() -> some View {
        Section(
            header: Text("数据"),
            footer: Button(action: { showingFormatHelp = true }) {
                Text("小说格式说明...")
                    .font(.footnote)
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
        ) {
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

            if let msg = importMessage {
                Text(msg).font(.footnote).foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func securityView() -> some View {
        Section(
            header: Text("隐私与安全"),
            footer: Text("关闭后，应用启动或回到前台将不再要求解锁，也不会显示安全遮罩。").font(
                .footnote
            ).foregroundColor(.secondary)
        ) {
            Toggle("启用安全遮罩（启动/前台需解锁）", isOn: $securityOverlayEnabled)
        }
    }

    @ViewBuilder
    private func appAppearanceView() -> some View {
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

    private func onPreviewButtonTapped() {
        showingPreviewImporter = true
    }

    private func onImportButtonTapped() {
        showingWriteImporter = true
    }

    private func onCompactButtonTapped() {
        dbManager.compactDatabase(hard: true) {
            compressionMessage = "全量压缩完成。"
            refreshStats()
        }
        compressionMessage = "已开始全量压缩（VACUUM），将在后台执行。"
    }

    private func showStats(result: DatabaseManager.DatabaseStats?) {
        if let s = result {
            func fmt(_ bytes: Int64) -> String {
                let kb = Double(bytes) / 1024
                let mb = kb / 1024
                if mb >= 1 { return String(format: "%.2f MB", mb) }
                if kb >= 1 { return String(format: "%.2f KB", kb) }
                return "\(bytes) B"
            }
            let lines = [
                "书籍总数: \(s.bookCount)",
                "数据库: \(fmt(s.dbSize))",
                "WAL: \(fmt(s.walSize))",
                "SHM: \(fmt(s.shmSize))",
                "页大小: \(s.pageSize) B",
                "空闲页: \(s.freelistCount)",
                "估算可回收: \(fmt(s.estimatedReclaimableBytes))",
            ]
            statsText = lines.joined(separator: "\n")
        } else {
            statsText = ""
        }
    }

    private func refreshStats() {
        let result = dbManager.getDatabaseStats()
        showStats(result: result)
    }

    private func refreshStatsAsync() {
        DispatchQueue.global(qos: .utility).async {
            let result = dbManager.getDatabaseStats()
            DispatchQueue.main.async {
                showStats(result: result)
            }
        }
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
