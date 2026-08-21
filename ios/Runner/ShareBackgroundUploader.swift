import Foundation

/// Drains the durable inbox via a background `URLSession` owned by the main
/// app, so delivery outlives both the Share Extension process and the
/// foreground app. Recreating the session with the same identifier at launch
/// flushes system-queued events from previous runs.
final class ShareBackgroundUploader: NSObject {
  static let shared = ShareBackgroundUploader()

  private let store = ShareBridgeStore.shared
  private let sessionIdentifier = "com.supanotes.share.background-upload"
  private var session: URLSession?

  /// Safe to call repeatedly: at launch (to collect queued events) and on
  /// every `retryPendingShares` channel call (e.g. after credential refresh).
  func resumePendingDelivery() {
    guard let item = store.readInboxItem(),
          let credentials = store.sessionCredentials()
    else { return }
    // Never deliver account A's pending share under account B.
    guard item.ownerUserId == credentials.ownerUserId else {
      store.clearInboxItem()
      return
    }
    guard var request = ShareAPIClient.makeRequest(
      baseURL: credentials.apiBaseUrl,
      accessToken: credentials.accessToken,
      item: item,
    ) else {
      store.clearInboxItem()
      return
    }
    request.timeoutInterval = 60

    let configuration = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
    configuration.sharedContainerIdentifier = "group.com.supanotes.shared"
    configuration.isDiscretionary = false
    session = URLSession(
      configuration: configuration,
      delegate: self,
      delegateQueue: nil,
    )
    session?.dataTask(with: request).resume()
  }
}

extension ShareBackgroundUploader: URLSessionDataDelegate {
  func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void,
  ) {
    if let http = response as? HTTPURLResponse {
      finish(with: http.statusCode)
    }
    completionHandler(.cancel)
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    if error != nil {
      // Network failure: keep the item; next launch/resume retries.
      return
    }
    // Status already handled in didReceiveResponse.
  }

  private func finish(with status: Int) {
    switch ShareAPIClient.classify(status: status) {
    case .confirmed, .droppedTerminal:
      store.clearInboxItem()
    case .retryLater, .waitForFreshCredentials:
      break // item kept for a future attempt with fresh credentials
    }
  }
}
