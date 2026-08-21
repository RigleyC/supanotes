import Foundation
import Security

struct SharedShareNote: Decodable {
  let noteId: String
  let title: String
  let preview: String
  let canEdit: Bool
}

struct SharedShareIndex: Decodable {
  let schemaVersion: Int
  let ownerUserId: String
  let notes: [SharedShareNote]
}

final class SharedShareStore {
  private let defaults = UserDefaults(suiteName: "group.com.supanotes.shared")!
  private let keychainService = "com.supanotes.share.session"
  private let keychainAccount = "session"
  private let keychainAccessGroup = "com.supanotes.share"
  private static let inboxKey = "share_inbox"

  func notes(forOwnerUserId ownerUserId: String?) -> [SharedShareNote] {
    guard let data = defaults.data(forKey: "notes_index"),
          let index = try? JSONDecoder().decode(SharedShareIndex.self, from: data),
          index.schemaVersion == 1,
          let ownerUserId,
          index.ownerUserId == ownerUserId
    else { return [] }
    return index.notes.filter(\.canEdit)
  }

  func savePending(text: String, noteId: String) {
    defaults.set(text, forKey: "pending_shared_text")
    defaults.set(noteId, forKey: "pending_shared_note_id")
  }

  func clearPending() {
    defaults.removeObject(forKey: "pending_shared_text")
    defaults.removeObject(forKey: "pending_shared_note_id")
    defaults.removeObject(forKey: "pending_shared_id")
  }

  // MARK: - Durable inbox (shared with the main app)

  func writeInboxItem(_ item: SharedInboxItem) {
    if let data = try? JSONEncoder().encode(item) {
      defaults.set(data, forKey: Self.inboxKey)
    }
  }

  func readInboxItem() -> SharedInboxItem? {
    guard let data = defaults.data(forKey: Self.inboxKey) else { return nil }
    return try? JSONDecoder().decode(SharedInboxItem.self, from: data)
  }

  func clearInboxItem() {
    defaults.removeObject(forKey: Self.inboxKey)
  }

  // MARK: - Session credentials (shared Keychain access group)

  struct SessionCredentials {
    let ownerUserId: String
    let accessToken: String
    let apiBaseUrl: String
  }

  func sessionCredentials() -> SessionCredentials? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: keychainAccount,
      kSecAttrAccessGroup as String: keychainAccessGroup,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: AnyObject?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
          let data = result as? Data,
          let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let ownerUserId = payload["ownerUserId"] as? String,
          let accessToken = payload["accessToken"] as? String,
          let apiBaseUrl = payload["apiBaseUrl"] as? String
    else { return nil }
    return SessionCredentials(
      ownerUserId: ownerUserId,
      accessToken: accessToken,
      apiBaseUrl: apiBaseUrl,
    )
  }
}
