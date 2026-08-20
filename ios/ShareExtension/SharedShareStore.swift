import Foundation

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

  func notes() -> [SharedShareNote] {
    guard let data = defaults.data(forKey: "notes_index"),
          let index = try? JSONDecoder().decode(SharedShareIndex.self, from: data)
    else { return [] }
    return index.notes.filter(\.canEdit)
  }

  func savePending(text: String) {
    defaults.set(text, forKey: "pending_shared_text")
  }
}
