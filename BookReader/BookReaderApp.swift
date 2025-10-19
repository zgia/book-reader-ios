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

    @State private var isUnlocked = false
    @State private var isAuthenticating = false
    @State private var hasRequestedInitialAuth = false
    @State private var externalOpenMessage: String?
    @State private var failedAttempts = 0
    @State private var lockUntil: Date?
    @State private var failureNonce = 0
    @State private var lockWorkItem: DispatchWorkItem?

    // 密码锁定策略常量
    private let attemptsToLock = 3
    private let firstLockedSeconds: TimeInterval = 60
    private let secondLockedSeconds: TimeInterval = 600

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
                        .zIndex(10000)
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
            .onChange(of: scenePhase) { _, newPhase in
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
                case .inactive:
                    // 进入非活跃状态时（按Home键、切换App等），立即关闭所有模态视图
                    // 这样可以确保安全遮罩层能正确覆盖内容，而不是被sheet或menu挡住
                    if PasscodeManager.shared.isPasscodeSet {
                        dismissAllModals()
                        // 立即上锁，显示遮罩层
                        isUnlocked = false
                    }
                case .background:
                    // 进入后台时再次确保上锁状态
                    if PasscodeManager.shared.isPasscodeSet {
                        isUnlocked = false
                        // 再次发送通知，确保所有模态视图都已关闭
                        dismissAllModals()
                    }
                default:
                    break
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .passcodeDidChange)
            ) { _ in
                // 密码变更后立即刷新状态：
                // 若设置了密码，保持解锁状态（刚设置完密码不应该立即要求输入）
                // 若移除了密码，直接解锁
                isUnlocked = true
                // 重置失败计数和锁定状态
                failedAttempts = 0
                lockUntil = nil
                lockWorkItem?.cancel()
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
        let name = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension

        var candidate = dir.appendingPathComponent(fileName)
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
    }

    // 确保 SecurityOverlayView 正确消失
    private func ensureSecurityOverlayDismissed() {
        // 如果当前场景是活跃状态且已解锁，强制更新视图状态
        // 这可以解决在某些边缘情况下 SecurityOverlayView 卡住的问题
        guard scenePhase == .active && isUnlocked else { return }

        DispatchQueue.main.async {
            // 触发视图更新
            self.isUnlocked = false
            DispatchQueue.main.async {
                self.isUnlocked = true
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
                startLock(for: firstLockedSeconds)  // 1 分钟
            } else if failedAttempts > attemptsToLock {
                startLock(for: secondLockedSeconds)  // 10 分钟
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

// 输入错误时的轻微左右抖动动画
private struct ShakeEffect: GeometryEffect {
    var travelDistance: CGFloat = 8
    var numberOfShakes: CGFloat = 2
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let x = travelDistance * sin(animatableData * .pi * numberOfShakes)
        return ProjectionTransform(CGAffineTransform(translationX: x, y: 0))
    }
}

private struct SecurityOverlayView: View {
    let showBlur: Bool
    let isUnlocked: Bool
    let onVerify: (String) -> Void
    let failedAttempts: Int
    let lockedUntil: Date?
    let failureNonce: Int

    @State private var input = ""
    @FocusState private var isFieldFocused: Bool

    private let shakeDuration: TimeInterval = 0.28

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
                        .foregroundColor(.secondary)
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
            restoreFocus(after: 0.15)
        }
        .onChange(of: isUnlocked) { oldValue, _ in
            if !oldValue {
                input = ""
                restoreFocus(after: 0.05)
            }
        }
        .onChange(of: lockedUntil) { _, _ in
            if !isLockedNow {
                restoreFocus(after: 0.05)
            }
        }
        .onChange(of: failureNonce) { _, _ in
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
            if isLockedNow {
                isFieldFocused = false
            }
            // 保留 6 个黑点完成抖动后再清空并恢复焦点
            DispatchQueue.main.asyncAfter(deadline: .now() + shakeDuration) {
                input = ""
                if !isLockedNow {
                    isFieldFocused = true
                }
            }
        }
    }

    // 辅助函数：延迟恢复输入焦点
    private func restoreFocus(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if !isLockedNow {
                isFieldFocused = true
            }
        }
    }

    @ViewBuilder
    private func passcodeInputView() -> some View {
        VStack(spacing: 12) {
            ZStack {
                // 6 位占位圆圈 + 填充黑点
                HStack(spacing: 16) {
                    ForEach(0..<6, id: \.self) { index in
                        ZStack {
                            Circle()
                                .stroke(.secondary, lineWidth: 1)
                                .frame(width: 18, height: 18)
                            if index < input.count {
                                Circle()
                                    .fill(Color.primary)
                                    .frame(width: 18, height: 18)
                                    .transition(.scale)
                            }
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if !isLockedNow { isFieldFocused = true }
                }
                .modifier(
                    ShakeEffect(
                        travelDistance: 8,  // 幅度
                        numberOfShakes: 4,  // 次数
                        animatableData: CGFloat(failureNonce)
                    )
                )
                .animation(
                    .easeInOut(duration: shakeDuration),
                    value: failureNonce
                )

                // 隐藏文本输入，用于接收数字与删除事件
                TextField("", text: $input)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($isFieldFocused)
                    .onChange(of: input) { _, newValue in
                        let digitsOnly = newValue.filter { $0.isNumber }
                        let normalized = String(digitsOnly.prefix(6))
                        if input != normalized { input = normalized }

                        // 在非锁定情况下，输入满 6 位先显示最后一个点，再触发校验
                        if !isLockedNow && normalized.count == 6 {
                            let code = normalized
                            DispatchQueue.main.asyncAfter(
                                deadline: .now() + 0.05
                            ) {
                                onVerify(code)
                            }
                        }
                    }
                    .frame(width: 0, height: 0)
                    .opacity(0.01)
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
        }
        .disabled(isLockedNow)
        .allowsHitTesting(!isLockedNow)
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
