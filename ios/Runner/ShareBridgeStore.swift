import Foundation
import Security

struct ShareSessionCredentials {
  let ownerUserId: String
  let accessToken: String
  let apiBaseUrl: String
}

/// Owns the Runner-side share storage contract: notes index, pending share,
/// durable inbox and session credentials. The inbox is shared with the Share
/// Extension through the App Group; credentials live in a shared Keychain
/// access group so both processes can read them.
final class ShareBridgeStore {
  static let shared = ShareBridgeStore()
  private let defaults = UserDefaults(suiteName: "group.com.supanotes.shared")!
  private let service = "com.supanotes.share.session"
  private static let inboxKey = "share_inbox"
  private let account = "session"
  private let accessGroup = "com.supanotes.share"

  func saveIndex(_ value: Any?) {
    guard let value else { return }
    if let data = try? JSONSerialization.data(withJSONObject: value) {
      defaults.set(data, forKey: "notes_index")
      defaults.synchronize()
    }
  }

  private var baseKeychainQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrAccessGroup as String: accessGroup,
    ]
  }

  func saveSession(_ value: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: value) else { return }
    defaults.set(data, forKey: "session_credentials")
    defaults.synchronize()
    SecItemDelete(baseKeychainQuery as CFDictionary)
    var query = baseKeychainQuery
    query[kSecValueData as String] = data
    query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
    SecItemAdd(query as CFDictionary, nil)
  }

  func sessionCredentials() -> ShareSessionCredentials? {
    if let data = defaults.data(forKey: "session_credentials"),
       let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let ownerUserId = payload["ownerUserId"] as? String,
       let accessToken = payload["accessToken"] as? String,
       let apiBaseUrl = payload["apiBaseUrl"] as? String {
      return ShareSessionCredentials(
        ownerUserId: ownerUserId,
        accessToken: accessToken,
        apiBaseUrl: apiBaseUrl
      )
    }
    var query = baseKeychainQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess,
          let data = result as? Data,
          let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    guard
      let ownerUserId = payload["ownerUserId"] as? String,
      let accessToken = payload["accessToken"] as? String,
      let apiBaseUrl = payload["apiBaseUrl"] as? String
    else { return nil }
    return ShareSessionCredentials(
      ownerUserId: ownerUserId,
      accessToken: accessToken,
      apiBaseUrl: apiBaseUrl
    )
  }

  // MARK: - Durable inbox (shared with the extension)

  func writeInboxItem(_ item: SharedInboxItem) {
    guard let data = try? JSONEncoder().encode(item) else { return }
    defaults.set(data, forKey: Self.inboxKey)
    defaults.synchronize()
  }

  func readInboxItem() -> SharedInboxItem? {
    guard let data = defaults.data(forKey: Self.inboxKey) else { return nil }
    return try? JSONDecoder().decode(SharedInboxItem.self, from: data)
  }

  func clearInboxItem() {
    defaults.removeObject(forKey: Self.inboxKey)
    defaults.synchronize()
  }

  // MARK: - Pending share (Flutter fallback path)

  func savePendingShare(text: String, noteId: String, ownerUserId: String? = nil, shareId: String? = nil) {
    defaults.set(text, forKey: "pending_shared_text")
    defaults.set(noteId, forKey: "pending_shared_note_id")
    defaults.set(shareId ?? UUID().uuidString.lowercased(), forKey: "pending_shared_id")
    if let ownerUserId {
      defaults.set(ownerUserId, forKey: "pending_shared_owner_user_id")
    }
    defaults.synchronize()
  }

  func clear() {
    defaults.removeObject(forKey: "notes_index")
    defaults.removeObject(forKey: "pending_shared_text")
    defaults.removeObject(forKey: "pending_shared_note_id")
    defaults.removeObject(forKey: "pending_shared_owner_user_id")
    defaults.removeObject(forKey: "pending_shared_id")
    defaults.removeObject(forKey: "session_credentials")
    defaults.removeObject(forKey: Self.inboxKey)
    defaults.synchronize()
    SecItemDelete(baseKeychainQuery as CFDictionary)
  }

  func readPendingShare() -> [String: String]? {
    guard let text = defaults.string(forKey: "pending_shared_text"), !text.isEmpty else { return nil }
    let shareId = defaults.string(forKey: "pending_shared_id") ?? UUID().uuidString.lowercased()
    defaults.set(shareId, forKey: "pending_shared_id")
    defaults.synchronize()
    var result = [
      "text": text,
      "noteId": defaults.string(forKey: "pending_shared_note_id") ?? "",
      "shareId": shareId,
    ]
    if let ownerUserId = defaults.string(forKey: "pending_shared_owner_user_id") {
      result["ownerUserId"] = ownerUserId
    }
    return result
  }

  func clearPendingShare() {
    defaults.removeObject(forKey: "pending_shared_text")
    defaults.removeObject(forKey: "pending_shared_note_id")
    defaults.removeObject(forKey: "pending_shared_owner_user_id")
    defaults.removeObject(forKey: "pending_shared_id")
    defaults.synchronize()
  }
}
