import Foundation

/// Inbox item persisted BEFORE user confirmation; drained by the in-extension
/// upload attempt and, if that fails, by the main app's background uploader.
/// Compiled into BOTH targets (extension + Runner).
struct SharedInboxItem: Codable, Equatable {
  let shareId: String
  let url: String
  let createdAt: String
  let noteId: String
  let ownerUserId: String
}

/// Pure helpers for the native share delivery path. Mirrors the Android
/// `ShareLinkText` / `ShareUploadPolicy` and the Dart client contract so all
/// three platforms accept the same shared text and classify failures alike.
enum ShareAPIClient {
  private static let trailingPunctuation: Set<Character> = [".", ",", ";", ":", "!", "?", ")", "]", "}"]

  /// Extracts the first http(s) URL, trimming trailing punctuation.
  static func extractUrl(from text: String?) -> String? {
    guard let text = text, !text.isEmpty else { return nil }
    let delimiters = CharacterSet.whitespacesAndNewlines
      .union(CharacterSet(charactersIn: "<>\"\u{201C}\u{201D}"))
    for token in text.components(separatedBy: delimiters) where !token.isEmpty {
      let lowered = token.lowercased()
      guard lowered.hasPrefix("http://") || lowered.hasPrefix("https://") else { continue }
      var value = token
      while let last = value.last, trailingPunctuation.contains(last) {
        value.removeLast()
      }
      return value.isEmpty ? nil : value
    }
    return nil
  }

  enum DeliveryAction {
    case confirmed
    case droppedTerminal
    case retryLater
    case waitForFreshCredentials
  }

  static func classify(status: Int) -> DeliveryAction {
    switch status {
    case 200...299:
      return .confirmed
    case 400, 403, 404:
      // Invalid URL / permission gone / note gone — never succeeds on retry.
      return .droppedTerminal
    case 401:
      return .waitForFreshCredentials
    default:
      return .retryLater
    }
  }

  static func makeRequest(
    baseURL: String,
    accessToken: String,
    item: SharedInboxItem,
  ) -> URLRequest? {
    let trimmedBase = baseURL.hasSuffix("/")
      ? String(baseURL.dropLast())
      : baseURL
    guard let url = URL(string: "\(trimmedBase)/notes/\(item.noteId)/shared-links") else {
      return nil
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 30
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.httpBody = try? JSONSerialization.data(withJSONObject: [
      "shareId": item.shareId,
      "url": item.url,
      "createdAt": item.createdAt,
    ])
    return request
  }
}
