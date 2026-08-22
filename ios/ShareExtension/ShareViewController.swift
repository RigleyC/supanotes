import Social
import SwiftUI
import UIKit

final class ShareViewController: UIViewController {
  private let store = SharedShareStore()

  override func viewDidLoad() {
    super.viewDidLoad()
    loadSharedText()
  }

  private func loadSharedText() {
    guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
          let provider = item.attachments?.first
    else {
      cancel(code: 1)
      return
    }
    let type = provider.hasItemConformingToTypeIdentifier("public.plain-text")
      ? "public.plain-text"
      : "public.url"
    provider.loadItem(forTypeIdentifier: type, options: nil) { [weak self] item, _ in
      DispatchQueue.main.async {
        self?.handleSharedItem(item)
      }
    }
  }

  private func handleSharedItem(_ item: Any?) {
    let text = (item as? String) ?? (item as? URL)?.absoluteString
    guard let text else {
      cancel(code: 2)
      return
    }
    guard let url = ShareAPIClient.extractUrl(from: text) else {
      presentMessage("O texto compartilhado não contém uma URL.")
      return
    }

    let credentials = store.sessionCredentials()
    let notes = store.notes(forOwnerUserId: credentials?.ownerUserId)
    if !notes.isEmpty {
      let activeCredentials = credentials ?? SharedShareStore.SessionCredentials(
        ownerUserId: store.ownerUserIdFromIndex() ?? "",
        accessToken: "",
        apiBaseUrl: "https://supanotes.fly.dev"
      )
      presentPicker(url: url, credentials: activeCredentials, notes: notes)
    } else {
      // No usable session/index yet: queue for the in-app picker so the link
      // survives until login — never silently discard (spec).
      store.savePending(text: text, noteId: "", ownerUserId: credentials?.ownerUserId)
      presentMessage("Abra o SupaNotes para escolher a nota.")
    }
  }

  private func presentPicker(
    url: String,
    credentials: SharedShareStore.SessionCredentials,
    notes: [SharedShareNote],
  ) {
    let view = ShareView(
      notes: notes,
      onCancel: { [weak self] in
        self?.extensionContext?.completeRequest(returningItems: nil)
      },
      onSelect: { [weak self] note in
        self?.deliver(url: url, note: note, ownerUserId: credentials.ownerUserId)
      }
    )
    host(view)
  }

  private func deliver(url: String, note: SharedShareNote, ownerUserId: String) {
    // Durable persistence BEFORE any confirmation (spec).
    let item = SharedInboxItem(
      shareId: UUID().uuidString.lowercased(),
      url: url,
      createdAt: ISO8601DateFormatter().string(from: Date()),
      noteId: note.noteId,
      ownerUserId: ownerUserId,
    )
    store.writeInboxItem(item)
    store.savePending(text: url, noteId: note.noteId, ownerUserId: ownerUserId)
    attemptImmediateDelivery(item)
    extensionContext?.completeRequest(returningItems: nil)
  }

  /// Best-effort upload while the extension still has runtime. On failure the
  /// inbox item stays queued for the main app's background uploader.
  private func attemptImmediateDelivery(_ item: SharedInboxItem) {
    guard let credentials = store.sessionCredentials(),
          var request = ShareAPIClient.makeRequest(
            baseURL: credentials.apiBaseUrl,
            accessToken: credentials.accessToken,
            item: item,
          )
    else { return }
    request.timeoutInterval = 15
    let task = URLSession.shared.dataTask(with: request) { [weak store] _, response, _ in
      let status = (response as? HTTPURLResponse)?.statusCode ?? -1
      switch ShareAPIClient.classify(status: status) {
      case .confirmed, .droppedTerminal:
        store?.clearInboxItem()
      case .retryLater, .waitForFreshCredentials:
        break // inbox item kept; main app retries with fresh credentials
      }
    }
    ProcessInfo.processInfo.performExpiringActivity(
      withReason: "Enviando link ao SupaNotes",
    ) { expired in
      if !expired {
        task.resume()
      }
    }
  }

  private func presentMessage(_ message: String) {
    host(ShareResultView(message: message) { [weak self] in
      self?.extensionContext?.completeRequest(returningItems: nil)
    })
  }

  private func cancel(code: Int) {
    extensionContext?.cancelRequest(withError: NSError(domain: "SupaNotesShare", code: code))
  }

  private func host(_ content: some View) {
    let controller = UIHostingController(rootView: content)
    addChild(controller)
    controller.view.frame = self.view.bounds
    controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    self.view.addSubview(controller.view)
    controller.didMove(toParent: self)
  }
}
