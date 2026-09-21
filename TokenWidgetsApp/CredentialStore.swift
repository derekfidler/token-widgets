import Foundation
import Security

/// Secrets used only by the host app (session cookies, admin API keys).
/// The widget extension never sees these — it only reads the computed UsageSnapshot cache.
enum CredentialKey: String, CaseIterable {
    case claudeSessionCookie   // full "name=value; name2=value2" Cookie header captured from claude.ai
    case claudeOrgId           // optional override; auto-discovered if empty
    case claudeUsageEndpointOverride // optional override for the personal usage endpoint path
    case claudeAnalyticsApiKey // Enterprise Analytics API key (starts with sk-ant-...)

    case chatgptSessionCookie  // full "name=value; name2=value2" Cookie header captured from chatgpt.com/openai.com
    case openaiAdminApiKey     // Admin API key for the Usage/Costs API
}

enum CredentialStore {
    private static let service = "dev.flatpay.tokenwidgets.credentials"

    /// Updates in place so a transient Keychain failure never deletes a working credential.
    @discardableResult
    static func set(_ value: String?, for key: CredentialKey) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        guard let value, !value.isEmpty else {
            let status = SecItemDelete(query as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        let data = Data(value.utf8)
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func get(_ key: CredentialKey) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func has(_ key: CredentialKey) -> Bool {
        guard let value = get(key) else { return false }
        return !value.isEmpty
    }
}
