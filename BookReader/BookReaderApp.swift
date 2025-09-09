import LocalAuthentication
import SwiftUI

// 通知名称扩展
extension Notification.Name {
    static let dismissAllModals = Notification.Name("dismissAllModals")
}

@main
struct NovelReaderApp: App {
    @StateObject private var db = DatabaseManager.shared
    @StateObject private var progressStore = ProgressStore()
    @StateObject private var appAppearance = AppAppearanceSettings()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("SecurityOverlayEnabled") private var securityOverlayEnabled:
        Bool = true

    @State private var isUnlocked: Bool = false
    @State private var authErrorMessage: String? = nil
    @State private var isAuthenticating: Bool = false
    @State private var hasRequestedInitialAuth: Bool = false
    @State private var activeModals: Set<String> = []

    init() {
        // 调试用，打印沙盒路径
        DebugUtils.printSandboxPaths()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                BookListView()
                    .environmentObject(db)
                    .environmentObject(progressStore)
                    .environmentObject(appAppearance)
                    .alert(
                        isPresented: Binding(
                            get: { db.needsDatabaseImport },
                            set: { _ in }
                        )
                    ) {
                        Alert(
                            title: Text("缺少数据库"),
                            message: Text(
                                "请连接手机到电脑，在 文件 → BookReader 文件夹 内放入 novel.sqlite"
                            ),
                            dismissButton: .default(Text("我知道了"))
                        )
                    }

                if securityOverlayEnabled
                    && (scenePhase != .active || !isUnlocked)
                {
                    SecurityOverlayView(
                        showBlur: true,
                        isUnlocked: isUnlocked,
                        message: authErrorMessage,
                        onRetry: { authenticate() }
                    )
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .zIndex(999)
                }
            }
            .preferredColorScheme(appAppearance.preferredColorScheme)
            .onAppear {
                // 仅首次进入时触发一次验证，避免视图重建导致反复调用
                if !hasRequestedInitialAuth {
                    hasRequestedInitialAuth = true
                    if securityOverlayEnabled {
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
                    if securityOverlayEnabled && !isUnlocked
                        && !isAuthenticating
                    {
                        // 延迟一点验证，确保模态视图已经完全消失
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            if securityOverlayEnabled && !self.isUnlocked
                                && !self.isAuthenticating
                            {
                                self.authenticate()
                            }
                        }
                    }
                case .background:
                    // 进入后台时立即上锁
                    if securityOverlayEnabled {
                        isUnlocked = false
                    }
                    // 取消所有活动的模态视图
                    dismissAllModals()
                default:
                    break
                }
            }
            .onChange(of: securityOverlayEnabled) { newValue, oldValue in
                if newValue {
                    // 开启安全遮罩后强制上锁并触发验证
                    isUnlocked = false
                    if !isAuthenticating {
                        authenticate()
                    }
                } else {
                    // 关闭安全遮罩后认为已解锁
                    isUnlocked = true
                    authErrorMessage = nil
                }
            }
        }
    }

    private func authenticate() {
        if isAuthenticating { return }
        isAuthenticating = true
        authErrorMessage = nil
        let context = LAContext()
        context.localizedCancelTitle = "取消"
        var error: NSError?

        let policy: LAPolicy = .deviceOwnerAuthentication
        if context.canEvaluatePolicy(policy, error: &error) {
            let reason = "验证以解锁应用"
            context.evaluatePolicy(policy, localizedReason: reason) {
                success,
                evalError in
                DispatchQueue.main.async {
                    if success {
                        isUnlocked = true
                        authErrorMessage = nil
                        isAuthenticating = false
                        // 确保界面状态正确，防止 SecurityOverlayView 卡住
                        self.ensureSecurityOverlayDismissed()
                    } else {
                        isUnlocked = false
                        isAuthenticating = false
                        if let laError = evalError as? LAError {
                            authErrorMessage = errorDescription(for: laError)
                        } else if let evalError = evalError {
                            authErrorMessage = evalError.localizedDescription
                        } else {
                            authErrorMessage = "验证失败"
                        }
                    }
                }
            }
        } else {
            // 无法评估策略（设备无生物识别/未设置密码等）
            DispatchQueue.main.async {
                isUnlocked = false
                isAuthenticating = false
                authErrorMessage =
                    (error as NSError?)?.localizedDescription
                    ?? "此设备不支持或未启用生物识别/密码"
            }
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

    private func errorDescription(for laError: LAError) -> String {
        switch laError.code {
        case .authenticationFailed: return "身份验证失败"
        case .userCancel: return "您已取消"
        case .userFallback: return "请使用密码"
        case .biometryNotAvailable: return "生物识别不可用"
        case .biometryNotEnrolled: return "未录入生物识别信息"
        case .biometryLockout: return "生物识别被锁定，请稍后再试"
        case .appCancel: return "应用已取消验证"
        case .systemCancel: return "系统已取消验证"
        default: return "验证未完成"
        }
    }
}

private struct SecurityOverlayView: View {
    var showBlur: Bool
    var isUnlocked: Bool
    var message: String?
    var onRetry: () -> Void

    var body: some View {
        ZStack {
            if showBlur {
                Rectangle()
                    .fill(.regularMaterial)
            }

            if !isUnlocked {
                // Color.black.opacity(0.6)
                VStack(spacing: 16) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundColor(.black.opacity(0.6))
                    Text("需要验证解锁")
                        .foregroundColor(.black)
                        .font(.headline)
                    if let message = message, !message.isEmpty {
                        Text(message)
                            .foregroundColor(.black.opacity(0.6))
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    Button(action: { onRetry() }) {
                        HStack {
                            Image(systemName: "faceid")
                            Text("使用Face ID解锁")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.white)
                        .foregroundColor(.black)
                        .cornerRadius(10)
                    }
                    .padding(.top, 8)
                }
                .padding(24)
            }
        }
    }
}
