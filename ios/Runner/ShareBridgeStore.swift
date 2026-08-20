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

  func savePendingShare(text: String, noteId: String) {
    defaults.set(text, forKey: "pending_shared_text")
    defaults.set(noteId, forKey: "pending_shared_note_id")
  }

  func clear() {
    defaults.removeObject(forKey: "notes_index")
    defaults.removeObject(forKey: "pending_shared_text")
    defaults.removeObject(forKey: "pending_shared_note_id")
    defaults.removeObject(forKey: "pending_shared_id")
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: "session",
    ]
    SecItemDelete(query as CFDictionary)
  }

  func readPendingShare() -> [String: String]? {
    guard let text = defaults.string(forKey: "pending_shared_text") else { return nil }
    let shareId = defaults.string(forKey: "pending_shared_id") ?? UUID().uuidString.lowercased()
    defaults.set(shareId, forKey: "pending_shared_id")
    return [
      "text": text,
      "noteId": defaults.string(forKey: "pending_shared_note_id") ?? "",
      "shareId": shareId,
    ]
  }

  func clearPendingShare() {
    defaults.removeObject(forKey: "pending_shared_text")
    defaults.removeObject(forKey: "pending_shared_note_id")
    defaults.removeObject(forKey: "pending_shared_id")
  }
}
