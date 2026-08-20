import Foundation
import Security

final class ShareBridgeStore {
  static let shared = ShareBridgeStore()
  private let defaults = UserDefaults(suiteName: "group.com.supanotes.shared")!
  private let service = "com.supanotes.share.session"

  func saveIndex(_ value: Any?) {
    guard let value else { return }
    if let data = try? JSONSerialization.data(withJSONObject: value) {
      defaults.set(data, forKey: "notes_index")
    }
  }

  func saveSession(_ value: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: value) else { return }
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: "session",
      kSecValueData as String: data,
    ]
    SecItemDelete(query as CFDictionary)
    SecItemAdd(query as CFDictionary, nil)
  }

  func clear() {
    defaults.removeObject(forKey: "notes_index")
    defaults.removeObject(forKey: "pending_shared_text")
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: "session",
    ]
    SecItemDelete(query as CFDictionary)
  }

  func readPendingShare() -> String? {
    defaults.string(forKey: "pending_shared_text")
  }

  func clearPendingShare() {
    defaults.removeObject(forKey: "pending_shared_text")
  }
}
