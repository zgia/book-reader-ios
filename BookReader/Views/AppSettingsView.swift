import SwiftUI
import UniformTypeIdentifiers

struct AppSettingsView: View {
    @EnvironmentObject private var appAppearance: AppAppearanceSettings
    @EnvironmentObject private var dbManager: DatabaseManager
    // 由是否设置密码决定是否启用安全遮罩

    @State private var showPreviewButton: Bool = false
    @State private var showingPreviewImporter: Bool = false
    @State private var showingWriteImporter: Bool = false
    @State private var importInProgress: Bool = false
    @State private var importMessage: String?
    @State private var compressionMessage: String?
    @State private var showingCompactConfirm: Bool = false
    @State private var statsText: String = ""
    @State private var showingFormatHelp: Bool = false
    @State private var securityDialog: SecurityDialog?
    @State private var securitySheet: SecuritySheet?
    @State private var passcodeInput: String = ""
    @State private var passcodeConfirmInput: String = ""
    @State private var passcodeTip: String?
    @FocusState private var setPasscodeFieldFocused: Bool
    @FocusState private var confirmPasscodeFieldFocused: Bool
    @FocusState private var removePasscodeFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                // 外观
                appAppearanceView()

                // 隐私与安全
                securityView()

                // 导入小说
                bookImporterView()

                // 数据库维护
                databaseMaintainerView()
            }
            .navigationTitle(String(localized: "setting.title"))
            .onAppear { refreshStatsAsync() }
            .sheet(isPresented: $showingFormatHelp) {
                textBookFormatHelpView()
            }
            .overlay(securityDialogOverlay())
            .sheet(item: $securitySheet) { sheet in
                if sheet == .setPasscode {
                    setPasscodeSheetView()
                } else {
                    removePasscodeSheetView()
                }
            }
        }
    }

    @ViewBuilder
    private func textBookFormatHelpView() -> some View {
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "btn_ok")) {
                        showingFormatHelp = false
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
    private func databaseMaintainerView() -> some View {
        Section(
            header: Text(String(localized: "db.maintenance.title")),
            footer: VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "db.maintenance.tip"))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        ) {
            HStack {
                Text(String(localized: "db.stats.title"))
                Spacer()
                Button(String(localized: "btn_refresh")) { refreshStats() }
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
                            ? String(localized: "db.compacting")
                            : String(localized: "db.compact")
                    )
                }
            }
            .disabled(dbManager.isCompacting)
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .alert(
                String(localized: "db.compact.confirm_title"),
                isPresented: $showingCompactConfirm
            ) {
                Button(String(localized: "btn_cancel"), role: .cancel) {}
                Button(String(localized: "btn_ok"), role: .destructive) {
                    onCompactButtonTapped()
                }
            } message: {
                Text(String(localized: "db.compact.confirm_message"))
            }
            if let cmsg = compressionMessage {
                Text(cmsg).font(.footnote).foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func bookImporterView() -> some View {
        Section(
            header: Text(String(localized: "data.section")),
            footer: Button(action: { showingFormatHelp = true }) {
                Text(String(localized: "format.help.button"))
                    .font(.footnote)
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
        ) {
            if showPreviewButton {
                Button(action: onPreviewButtonTapped) {
                    Text(String(localized: "import.preview"))
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
                    Text(
                        importInProgress
                            ? String(localized: "import.in_progress")
                            : String(localized: "import.start")
                    )
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
            header: Text(String(localized: "security.title")),
            footer: Text(String(localized: "security.tip")).font(
                .footnote
            ).foregroundColor(.secondary)
        ) {
            if PasscodeManager.shared.isPasscodeSet {
                HStack {
                    Image(systemName: "key.fill").foregroundColor(.green)
                    Text(String(localized: "security.passcode_set"))
                    Spacer()
                    Button(
                        String(localized: "security.remove_passcode"),
                        role: .destructive
                    ) {
                        passcodeInput = ""
                        passcodeTip = nil
                        securityDialog = .removePasscode
                    }
                    .font(.footnote)
                }
            } else {
                HStack {
                    Image(systemName: "key.slash.fill").foregroundColor(
                        .secondary
                    )
                    Text(String(localized: "security.passcode_not_set"))
                    Spacer()
                    Button(String(localized: "security.set_passcode")) {
                        passcodeInput = ""
                        passcodeConfirmInput = ""
                        passcodeTip = nil
                        securityDialog = .setPasscode
                    }
                    .font(.footnote)
                }
            }
        }

    }

    // MARK: - Sheets
    private func setPasscodeSheetView() -> some View {
        NavigationStack {
            Form {
                Section(
                    footer: Text(
                        passcodeTip
                            ?? String(
                                localized: "security.passcode_requirement"
                            )
                    ).font(.footnote)
                        .foregroundColor(.secondary)
                ) {
                    SecureField(
                        String(localized: "security.enter_new_passcode"),
                        text: $passcodeInput
                    )
                    .keyboardType(.numberPad)
                    .onChange(of: passcodeInput) { newValue, _ in
                        passcodeInput = String(
                            newValue.filter { $0.isNumber }.prefix(6)
                        )
                    }
                    .focused($setPasscodeFieldFocused)
                    SecureField(
                        String(localized: "security.enter_again"),
                        text: $passcodeConfirmInput
                    )
                    .keyboardType(.numberPad)
                    .onChange(of: passcodeConfirmInput) { newValue, _ in
                        passcodeConfirmInput = String(
                            newValue.filter { $0.isNumber }.prefix(6)
                        )
                    }
                    .focused($confirmPasscodeFieldFocused)
                }
            }
            .navigationTitle(String(localized: "security.set_passcode_title"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "btn_cancel")) {
                        securitySheet = nil
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "btn_save")) {
                        guard passcodeInput.count == 6,
                            passcodeInput == passcodeConfirmInput
                        else {
                            passcodeTip = String(
                                localized:
                                    "security.passcode_mismatch_or_invalid"
                            )
                            return
                        }
                        do {
                            try PasscodeManager.shared.setPasscode(
                                passcodeInput
                            )
                            passcodeTip = String(
                                localized: "security.passcode_set_done"
                            )
                            securitySheet = nil
                            NotificationCenter.default.post(
                                name: .passcodeDidChange,
                                object: nil
                            )
                        } catch {
                            passcodeTip = String(
                                format: String(
                                    localized: "security.save_failed"
                                ),
                                error.localizedDescription
                            )
                        }
                    }
                    .disabled(
                        passcodeInput.count != 6
                            || passcodeConfirmInput.count != 6
                    )
                }
            }
            .onAppear {
                passcodeInput = ""
                passcodeConfirmInput = ""
                passcodeTip = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    setPasscodeFieldFocused = true
                }
            }
            .onDisappear {
                passcodeInput = ""
                passcodeConfirmInput = ""
                passcodeTip = nil
                setPasscodeFieldFocused = false
                confirmPasscodeFieldFocused = false
            }
        }
        .presentationDetents([.medium])
    }

    private func removePasscodeSheetView() -> some View {
        NavigationStack {
            Form {
                Section(
                    footer: Text(
                        passcodeTip
                            ?? String(
                                localized:
                                    "security.enter_current_passcode_to_remove"
                            )
                    ).font(
                        .footnote
                    ).foregroundColor(.secondary)
                ) {
                    SecureField(
                        String(localized: "security.current_passcode"),
                        text: $passcodeInput
                    )
                    .keyboardType(.numberPad)
                    .onChange(of: passcodeInput) { newValue, _ in
                        passcodeInput = String(
                            newValue.filter { $0.isNumber }.prefix(6)
                        )
                    }
                    .focused($removePasscodeFieldFocused)
                }
            }
            .navigationTitle(
                String(localized: "security.remove_passcode_title")
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "btn_cancel")) {
                        securitySheet = nil
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "btn_remove"), role: .destructive)
                    {
                        if PasscodeManager.shared.verifyPasscode(passcodeInput)
                        {
                            do {
                                try PasscodeManager.shared.removePasscode()
                                passcodeTip = String(
                                    localized: "security.passcode_removed"
                                )
                                securitySheet = nil
                                NotificationCenter.default.post(
                                    name: .passcodeDidChange,
                                    object: nil
                                )
                            } catch {
                                passcodeTip =
                                    String(
                                        format: String(
                                            localized: "security.remove_failed"
                                        ),
                                        error.localizedDescription
                                    )
                            }
                        } else {
                            passcodeTip = String(
                                localized: "security.passcode_error"
                            )
                        }
                    }
                    .disabled(passcodeInput.count != 6)
                }
            }
            .onAppear {
                passcodeInput = ""
                passcodeTip = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    removePasscodeFieldFocused = true
                }
            }
            .onDisappear {
                passcodeInput = ""
                passcodeTip = nil
                removePasscodeFieldFocused = false
            }
        }
        .presentationDetents([.medium])
    }

    private enum SecuritySheet: Identifiable, Equatable {
        case setPasscode
        case removePasscode
        var id: String { self == .setPasscode ? "set" : "remove" }
    }

    @ViewBuilder
    private func appAppearanceView() -> some View {
        Section(header: Text(String(localized: "appearance.title"))) {
            Picker(
                String(localized: "appearance.set_appearance"),
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
            compressionMessage = String(localized: "db.compact.done")
            refreshStats()
        }
        compressionMessage = String(localized: "db.compact.started")
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
                String(
                    format: String(localized: "db.stats.book_count"),
                    s.bookCount
                ),
                String(
                    format: String(localized: "db.stats.db_size"),
                    fmt(s.dbSize)
                ),
                String(
                    format: String(localized: "db.stats.wal_size"),
                    fmt(s.walSize)
                ),
                String(
                    format: String(localized: "db.stats.shm_size"),
                    fmt(s.shmSize)
                ),
                String(
                    format: String(localized: "db.stats.page_size"),
                    s.pageSize
                ),
                String(
                    format: String(localized: "db.stats.freelist_count"),
                    s.freelistCount
                ),
                String(
                    format: String(localized: "db.stats.estimated_reclaimable"),
                    fmt(s.estimatedReclaimableBytes)
                ),
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
                        importMessage = String(
                            format: String(
                                localized: "import.preview_failed"
                            ),
                            error.localizedDescription
                        )
                    }
                }
            }
        case .failure(let error):
            importMessage = String(
                format: String(
                    localized: "import.file_select_failed"
                ),
                error.localizedDescription
            )
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
                        importMessage = String(localized: "import.done")
                    }
                } catch {
                    DispatchQueue.main.async {
                        importInProgress = false
                        importMessage = String(
                            format: String(
                                localized: "import.failed"
                            ),
                            error.localizedDescription
                        )
                    }
                }
            }
        case .failure(let error):
            importMessage = String(
                format: String(
                    localized: "import.file_select_failed"
                ),
                error.localizedDescription
            )
        }
    }

    // MARK: - Dialog Overlay
    @ViewBuilder
    private func securityDialogOverlay() -> some View {
        if let dialog = securityDialog {
            ZStack {
                Color.black.opacity(0.35).ignoresSafeArea()
                VStack(spacing: 16) {
                    Text(
                        dialog == .setPasscode
                            ? String(localized: "security.set_passcode_title")
                            : String(
                                localized: "security.remove_passcode_title"
                            )
                    )
                    .font(.headline)
                    if dialog == .setPasscode {
                        VStack(spacing: 10) {
                            SecureField(
                                String(
                                    localized: "security.enter_new_passcode"
                                ),
                                text: $passcodeInput
                            )
                            .keyboardType(.numberPad)
                            .focused($setPasscodeFieldFocused)
                            .onChange(of: passcodeInput) { newValue, _ in
                                let filtered = String(
                                    newValue.filter { $0.isNumber }.prefix(
                                        6
                                    )
                                )
                                if filtered != newValue {
                                    passcodeInput = filtered
                                }
                            }
                            .textContentType(.oneTimeCode)
                            .padding(10)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            SecureField(
                                String(localized: "security.enter_again"),
                                text: $passcodeConfirmInput
                            )
                            .keyboardType(.numberPad)
                            .focused($confirmPasscodeFieldFocused)
                            .onChange(of: passcodeConfirmInput) {
                                newValue,
                                _ in
                                let filtered = String(
                                    newValue.filter { $0.isNumber }.prefix(
                                        6
                                    )
                                )
                                if filtered != newValue {
                                    passcodeConfirmInput = filtered
                                }
                            }
                            .textContentType(.oneTimeCode)
                            .padding(10)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    } else {
                        SecureField(
                            String(localized: "security.current_passcode"),
                            text: $passcodeInput
                        )
                        .keyboardType(.numberPad)
                        .focused($removePasscodeFieldFocused)
                        .onChange(of: passcodeInput) { newValue, _ in
                            let filtered = String(
                                newValue.filter { $0.isNumber }.prefix(6)
                            )
                            if filtered != newValue {
                                passcodeInput = filtered
                            }
                        }
                        .textContentType(.oneTimeCode)
                        .padding(10)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    if let tip = passcodeTip, !tip.isEmpty {
                        Text(tip)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    HStack {
                        Button(String(localized: "btn_cancel")) {
                            securityDialog = nil
                        }
                        .frame(maxWidth: .infinity)
                        Button(
                            dialog == .setPasscode
                                ? String(localized: "btn_save")
                                : String(localized: "btn_remove")
                        ) {
                            handleSecurityDialogPrimaryAction(dialog)
                        }
                        .disabled(
                            dialog == .setPasscode
                                ? !(passcodeInput.count == 6
                                    && passcodeConfirmInput.count == 6)
                                : passcodeInput.count != 6
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(20)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 40)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        switch dialog {
                        case .setPasscode: setPasscodeFieldFocused = true
                        case .removePasscode: removePasscodeFieldFocused = true
                        }
                    }
                }
            }
        } else {
            EmptyView()
        }
    }

    private func handleSecurityDialogPrimaryAction(_ dialog: SecurityDialog) {
        switch dialog {
        case .setPasscode:
            guard passcodeInput.count == 6,
                passcodeInput == passcodeConfirmInput
            else {
                passcodeTip = String(
                    localized: "security.passcode_mismatch_or_invalid"
                )
                return
            }
            do {
                try PasscodeManager.shared.setPasscode(passcodeInput)
                passcodeTip = String(localized: "security.passcode_set_done")
                securityDialog = nil
                NotificationCenter.default.post(
                    name: .passcodeDidChange,
                    object: nil
                )
            } catch {
                passcodeTip = String(
                    format: String(localized: "security.save_failed"),
                    error.localizedDescription
                )
            }
        case .removePasscode:
            if PasscodeManager.shared.verifyPasscode(passcodeInput) {
                do {
                    try PasscodeManager.shared.removePasscode()
                    passcodeTip = String(localized: "security.passcode_removed")
                    securityDialog = nil
                    NotificationCenter.default.post(
                        name: .passcodeDidChange,
                        object: nil
                    )
                } catch {
                    passcodeTip = String(
                        format: String(localized: "security.remove_failed"),
                        error.localizedDescription
                    )
                }
            } else {
                passcodeTip = String(localized: "security.passcode_error")
            }
        }
        passcodeInput = ""
        passcodeConfirmInput = ""
    }

    private enum SecurityDialog: Equatable {
        case setPasscode
        case removePasscode
        var title: String {
            self == .setPasscode
                ? String(localized: "security.set_passcode_title")
                : String(localized: "security.remove_passcode_title")
        }
        var primaryActionTitle: String {
            self == .setPasscode
                ? String(localized: "btn_save")
                : String(localized: "btn_remove")
        }
    }
}

#Preview("AppSettingsView") {
    AppSettingsView()
        .environmentObject(AppAppearanceSettings())
        .environmentObject(DatabaseManager.shared)
}
