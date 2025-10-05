import SwiftUI
import UIKit

// 通知名称扩展
extension Notification.Name {
    static let dismissAllModals = Notification.Name("dismissAllModals")
    static let passcodeDidChange = Notification.Name("passcodeDidChange")
    static let categoriesDidChange = Notification.Name("categoriesDidChange")
}

@main
struct BookReaderApp: App {
    @StateObject private var db = DatabaseManager.shared
    @StateObject private var progressStore = ProgressStore()
    @StateObject private var appSettings = AppSettings()
    @Environment(\.scenePhase) private var scenePhase

    @State private var isUnlocked: Bool = false
    @State private var isAuthenticating: Bool = false
    @State private var hasRequestedInitialAuth: Bool = false
    @State private var activeModals: Set<String> = []
    @State private var externalOpenMessage: String? = nil
    @State private var failedAttempts: Int = 0
    @State private var attemptsToLock: Int = 3
    @State private var firstLockedMinute: Double = 1
    @State private var secondLockedMinutes: Double = 10
    @State private var lockUntil: Date? = nil
    @State private var failureNonce: Int = 0
    @State private var lockWorkItem: DispatchWorkItem? = nil

    init() {
        // 调试用，打印沙盒路径
        DebugUtils.printSandboxPaths()
    }

    var body: some Scene {
        WindowGroup {
            ReadingSettingsProvider {
                ZStack {
                    BookListView()
                        .environmentObject(db)
                        .environmentObject(progressStore)
                        .environmentObject(appSettings)
                        .alert(
                            isPresented: Binding(
                                get: { db.initError != nil },
                                set: { _ in }
                            )
                        ) {
                            Alert(
                                title: Text(
                                    String(localized: "db.init_failed")
                                ),
                                message: Text(db.initError ?? ""),
                                dismissButton: .default(
                                    Text(String(localized: "btn.ok"))
                                )
                            )
                        }

                    if PasscodeManager.shared.isPasscodeSet
                        && (scenePhase != .active || !isUnlocked)
                    {
                        SecurityOverlayView(
                            showBlur: true,
                            isUnlocked: isUnlocked,
                            onVerify: { code in onVerifyPasscode(code) },
                            failedAttempts: failedAttempts,
                            lockedUntil: lockUntil,
                            failureNonce: failureNonce
                        )
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .zIndex(999)
                    }
                }
            }
            .preferredColorScheme(appSettings.preferredColorScheme)
            .onOpenURL(perform: handleOpenURL)
            .alert(
                isPresented: Binding(
                    get: { externalOpenMessage != nil },
                    set: { if !$0 { externalOpenMessage = nil } }
                )
            ) {
                Alert(
                    title: Text(String(localized: "import.done")),
                    message: Text(externalOpenMessage ?? ""),
                    dismissButton: .default(Text(String(localized: "btn.ok")))
                )
            }
            .onAppear {
                // 仅首次进入时触发一次验证，避免视图重建导致反复调用
                if !hasRequestedInitialAuth {
                    hasRequestedInitialAuth = true
                    if PasscodeManager.shared.isPasscodeSet {
                        authenticate()
                    } else {
                        isUnlocked = true
                    }
                }
            }
            .onChange(of: scenePhase) { newPhase, oldPhase in
                switch newPhase {
                case .active:
                    // 回到前台时如果未解锁则再次验证（防抖）
                    if PasscodeManager.shared.isPasscodeSet && !isUnlocked
                        && !isAuthenticating
                    {
                        // 延迟一点验证，确保模态视图已经完全消失
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            if PasscodeManager.shared.isPasscodeSet
                                && !self.isUnlocked
                                && !self.isAuthenticating
                            {
                                self.authenticate()
                            }
                        }
                    }
                case .background:
                    // 进入后台时立即上锁
                    if PasscodeManager.shared.isPasscodeSet {
                        isUnlocked = false
                    }
                    // 取消所有活动的模态视图
                    dismissAllModals()
                default:
                    break
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .passcodeDidChange)
            ) { _ in
                // 密码变更后立即刷新状态：
                // 若设置了密码，不立刻上锁；若移除了密码，直接解锁
                if PasscodeManager.shared.isPasscodeSet {
                    isUnlocked = true
                } else {
                    isUnlocked = true
                }
            }
        }
    }

    private func handleOpenURL(_ url: URL) {
        // 仅处理文本类型
        let allowedExts: Set<String> = ["txt", "text"]
        let ext = url.pathExtension.lowercased()
        guard allowedExts.contains(ext) else { return }

        let uploadsDir = WebUploadServer.shared.uploadsDirectory()
        do {
            try FileManager.default.createDirectory(
                at: uploadsDir,
                withIntermediateDirectories: true
            )

            // 安全作用域访问（跨 App 打开场景）
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

            // 目标命名去重
            let destURL = uniqueDestination(in: uploadsDir, for: url)
            try FileManager.default.copyItem(at: url, to: destURL)

            // 刷新上传列表并提示
            WebUploadServer.shared.refreshUploadedFiles()
            DispatchQueue.main.async {
                let fileName = destURL.lastPathComponent
                externalOpenMessage = String(
                    format: String(localized: "import.external_saved_x"),
                    fileName
                )
            }
        } catch {
            // 简单记录
            Log.debug("openURL copy failed: \(error.localizedDescription)")
        }
    }

    private func uniqueDestination(in dir: URL, for sourceURL: URL) -> URL {
        let fileName = sourceURL.lastPathComponent
        var candidate = dir.appendingPathComponent(fileName)
        let name = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var index = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let newName = "\(name)-\(index).\(ext.isEmpty ? "txt" : ext)"
            candidate = dir.appendingPathComponent(newName)
            index += 1
        }
        return candidate
    }

    private func authenticate() {
        if isAuthenticating { return }
        isAuthenticating = true
        // 若未设置密码，直接解锁；否则显示提示，等待用户输入
        if PasscodeManager.shared.isPasscodeSet {
            isUnlocked = false
            isAuthenticating = false
            // 固定文案通过界面展示，无需单独状态
        } else {
            isUnlocked = true
            isAuthenticating = false
            self.ensureSecurityOverlayDismissed()
        }
    }

    // 取消所有活动的模态视图
    private func dismissAllModals() {

        // 通过发送通知来取消所有活动的模态视图
        NotificationCenter.default.post(name: .dismissAllModals, object: nil)
        activeModals.removeAll()
    }

    // 确保 SecurityOverlayView 正确消失
    private func ensureSecurityOverlayDismissed() {
        // 如果当前场景是活跃状态且已解锁，但仍有 SecurityOverlayView 显示问题
        // 可以在这里添加额外的清理逻辑
        guard scenePhase == .active && isUnlocked else { return }

        // 强制更新视图状态，确保 SecurityOverlayView 正确消失
        // 这可以解决在某些边缘情况下 SecurityOverlayView 卡住的问题
        let currentIsUnlocked = isUnlocked
        let currentScenePhase = scenePhase

        // 如果状态正确但仍有显示问题，短暂重置状态再恢复
        if currentIsUnlocked && currentScenePhase == .active {
            DispatchQueue.main.async {
                // 触发视图更新
                self.isUnlocked = false
                DispatchQueue.main.async {
                    self.isUnlocked = true
                }
            }
        }
    }

    // 校验输入的密码
    private func onVerifyPasscode(_ code: String) {
        if PasscodeManager.shared.verifyPasscode(code) {
            isUnlocked = true
            failedAttempts = 0
            lockUntil = nil
            lockWorkItem?.cancel()
            ensureSecurityOverlayDismissed()
        } else {
            isUnlocked = false
            // 失败计数与锁定策略
            failedAttempts += 1
            failureNonce &+= 1

            if failedAttempts == attemptsToLock {
                startLock(for: firstLockedMinute * 10)  // 1 分钟
            } else if failedAttempts > attemptsToLock {
                startLock(for: secondLockedMinutes * 10)  // 10 分钟
            }
        }
    }

    // 启动锁定计时并在到期后自动解除
    private func startLock(for seconds: TimeInterval) {
        lockWorkItem?.cancel()
        let until = Date().addingTimeInterval(seconds)
        lockUntil = until
        let work = DispatchWorkItem {
            self.lockUntil = nil
        }
        lockWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}

private struct SecurityOverlayView: View {
    var showBlur: Bool
    var isUnlocked: Bool
    var onVerify: (String) -> Void
    var failedAttempts: Int = 0
    var lockedUntil: Date? = nil
    var failureNonce: Int = 0

    @State private var input: String = ""
    @FocusState private var isFieldFocused: Bool

    private var isLockedNow: Bool {
        if let lockedUntil, lockedUntil > Date() { return true }
        return false
    }

    var body: some View {
        ZStack {
            if showBlur {
                Rectangle()
                    .fill(.regularMaterial)
            }

            if !isUnlocked {
                VStack(spacing: 16) {
                    Image(systemName: "lock")
                        .font(.system(size: 50, weight: .semibold))
                        .foregroundStyle(.blue)
                        .padding(.bottom, 8)
                    Text(String(localized: "security.auth_to_unlock"))
                        .font(.headline)
                    Text(String(localized: "security.input_passcode_to_unlock"))
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    passcodeInputView()

                    unthFailedAttemptsView()

                }
                .padding(24)
                .offset(y: -160)
            }
        }
        .onAppear {
            input = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                if !isLockedNow { isFieldFocused = true }
            }
        }
        .onChange(of: isUnlocked) { newValue, _ in
            if !newValue {
                input = ""
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    if !isLockedNow { isFieldFocused = true }
                }
            }
        }
        .onChange(of: lockedUntil) { _, _ in
            if !isLockedNow {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isFieldFocused = true
                }
            }
        }
        .onChange(of: failureNonce) { _, _ in
            input = ""
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
            if isLockedNow {
                isFieldFocused = false
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isFieldFocused = true
                }
            }
        }
        .onChange(of: failedAttempts) { oldValue, newValue in
            guard newValue > oldValue else { return }
            input = ""
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
            if !isLockedNow {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isFieldFocused = true
                }
            }
        }
    }

    @ViewBuilder
    private func passcodeInputView() -> some View {
        VStack(spacing: 10) {
            SecureField(
                String(
                    localized: "security.passcode_placeholder"
                ),
                text: $input
            )
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .multilineTextAlignment(.center)
            .focused($isFieldFocused)
            .onChange(of: input) { newValue, _ in
                let digitsOnly = newValue.filter { $0.isNumber }
                let normalized = String(digitsOnly.prefix(6))
                if input != normalized { input = normalized }

                // 在非锁定情况下，输入满 6 位即提交
                if !isLockedNow && normalized.count == 6 {
                    let code = normalized
                    onVerify(code)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .cornerRadius(10)
            .background(
                RoundedRectangle(
                    cornerRadius: 10,
                    style: .continuous
                )
                .fill(.thinMaterial)
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: 10,
                    style: .continuous
                )
                .stroke(Color(UIColor.separator), lineWidth: 1)
            )
            .disabled(isLockedNow)
            .allowsHitTesting(!isLockedNow)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func unthFailedAttemptsView() -> some View {
        ZStack {
            if isLockedNow {
                errorBanner(String(localized: "security.locked_for_a_while"))
            } else if failedAttempts > 0 {
                errorBanner(
                    String(
                        format: String(localized: "security.failed_attempts_x"),
                        failedAttempts
                    )
                )
            }
        }
        .frame(height: 44)
    }

    private func errorBanner(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundColor(.white)
            .padding(.horizontal, 36)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(Color.red)
            )
            .padding(.top, 8)
    }
}
