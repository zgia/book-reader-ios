import LocalAuthentication
import SwiftUI

@main
struct NovelReaderApp: App {
    @StateObject private var db = DatabaseManager.shared
    @StateObject private var progressStore = ProgressStore()
    @StateObject private var settings = ThemeSettings()
    @StateObject private var appAppearance = AppAppearanceSettings()
    @Environment(\.scenePhase) private var scenePhase

    @State private var isUnlocked: Bool = false
    @State private var authErrorMessage: String? = nil
    @State private var isAuthenticating: Bool = false
    @State private var hasRequestedInitialAuth: Bool = false

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
                    .environmentObject(settings)
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

                if scenePhase != .active || !isUnlocked {
                    SecurityOverlayView(
                        showBlur: true,
                        isUnlocked: isUnlocked,
                        message: authErrorMessage,
                        onRetry: { authenticate() }
                    )
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .zIndex(2)
                }
            }
            .preferredColorScheme(appAppearance.preferredColorScheme)
            .onAppear {
                // 仅首次进入时触发一次验证，避免视图重建导致反复调用
                if !hasRequestedInitialAuth {
                    hasRequestedInitialAuth = true
                    authenticate()
                }
            }
            .onChange(of: scenePhase) { newPhase, oldPhase in
                switch newPhase {
                case .active:
                    // 回到前台时如果未解锁则再次验证（防抖）
                    if !isUnlocked && !isAuthenticating { authenticate() }
                case .background:
                    // 进入后台时立即上锁
                    isUnlocked = false
                default:
                    break
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
