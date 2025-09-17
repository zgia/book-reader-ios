import Foundation
import Security
import CryptoKit

/// 管理应用的6位数字密码，使用 Keychain 安全存储（仅存储哈希）
struct PasscodeManager {
    static let shared = PasscodeManager()

    private let service = "net.zgia.BookReader.passcode"
    private let account = "appPasscode"

    /// 是否已设置密码
    var isPasscodeSet: Bool {
        loadHash() != nil
    }

    /// 设置/更新6位密码
    func setPasscode(_ passcode: String) throws {
        guard Self.isValid(passcode) else { throw PasscodeError.invalidFormat }
        let hash = Self.sha256(passcode)
        if loadHash() == nil {
            try saveHash(hash)
        } else {
            try updateHash(hash)
        }
    }

    /// 校验输入密码是否正确
    func verifyPasscode(_ passcode: String) -> Bool {
        guard Self.isValid(passcode), let stored = loadHash() else { return false }
        return stored == Self.sha256(passcode)
    }

    /// 移除密码
    func removePasscode() throws {
        try deleteHash()
    }

    // MARK: - Private
    private func saveHash(_ hash: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: hash,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess { throw PasscodeError.keychain(status) }
    }

    private func updateHash(_ hash: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attrs: [String: Any] = [kSecValueData as String: hash]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            try saveHash(hash)
            return
        }
        if status != errSecSuccess { throw PasscodeError.keychain(status) }
    }

    private func loadHash() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess { return item as? Data }
        return nil
    }

    private func deleteHash() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw PasscodeError.keychain(status)
        }
    }

    private static func sha256(_ text: String) -> Data {
        let data = Data(text.utf8)
        let digest = SHA256.hash(data: data)
        return Data(digest)
    }

    private static func isValid(_ passcode: String) -> Bool {
        passcode.count == 6 && passcode.allSatisfy { $0.isNumber }
    }
}

enum PasscodeError: Error, LocalizedError {
    case invalidFormat
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidFormat: return "密码必须是6位数字"
        case .keychain(let status): return "Keychain错误: \(status)"
        }
    }
}


