import SwiftUI
import UIKit

// 通知名称扩展
extension Notification.Name {
    static let dismissAllModals = Notification.Name("dismissAllModals")
    static let passcodeDidChange = Notification.Name("passcodeDidChange")
    static let categoriesDidChange = Notification.Name("categoriesDidChange")
}

@main
struct NovelReaderApp: App {
    @StateObject private var db = DatabaseManager.shared
    @StateObject private var progressStore = ProgressStore()
    @StateObject private var appSettings = AppSettings()
    @Environment(\.scenePhase) private var scenePhase

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
                            message: authErrorMessage,
                            onVerify: { code in onVerifyPasscode(code) }
                        )
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .zIndex(999)
                    }
                }
            }
            .preferredColorScheme(appSettings.preferredColorScheme)
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
                    authErrorMessage = nil
                } else {
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
        // 若未设置密码，直接解锁；否则显示提示，等待用户输入
        if PasscodeManager.shared.isPasscodeSet {
            isUnlocked = false
            isAuthenticating = false
            authErrorMessage = String(
                localized: "security.input_6_digital_passcode"
            )
        } else {
            isUnlocked = true
            isAuthenticating = false
            authErrorMessage = nil
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
            authErrorMessage = nil
            ensureSecurityOverlayDismissed()
        } else {
            isUnlocked = false
            authErrorMessage = String(
                localized: "security.passcode_error_and_try_again"
            )
        }
    }
}

private struct SecurityOverlayView: View {
    var showBlur: Bool
    var isUnlocked: Bool
    var message: String?
    var onVerify: (String) -> Void

    @State private var input: String = ""
    @FocusState private var isFieldFocused: Bool

    private var displayMessage: String {
        if let message, !message.isEmpty {
            return message
        }
        return String(localized: "security.input_6_digital_passcode")
    }

    var body: some View {
        ZStack {
            if showBlur {
                Rectangle()
                    .fill(.regularMaterial)
            }

            if !isUnlocked {
                VStack(spacing: 16) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 44, weight: .semibold))
                    Text(String(localized: "security.auth_to_unlock"))
                        .font(.headline)
                    Text(displayMessage)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    VStack(spacing: 10) {
                        SecureField(
                            String(
                                localized: "security.input_6_digital_passcode"
                            ),
                            text: $input
                        )
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .multilineTextAlignment(.center)
                        .focused($isFieldFocused)
                        .onChange(of: input) { newValue, _ in
                            let filtered = newValue.filter { $0.isNumber }
                            input = String(filtered.prefix(6))

                            if input.count == 6 {
                                onVerify(input)
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
                    }
                    .padding(.top, 8)
                }
                .padding(24)
            }
        }
        .onAppear {
            input = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isFieldFocused = true
            }
        }
        .onChange(of: isUnlocked) { newValue, _ in
            if !newValue {
                input = ""
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isFieldFocused = true
                }
            }
        }
    }
}
