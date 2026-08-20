import Social
import SwiftUI

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
      extensionContext?.cancelRequest(withError: NSError(domain: "SupaNotesShare", code: 1))
      return
    }
    let type = provider.hasItemConformingToTypeIdentifier("public.plain-text")
      ? "public.plain-text"
      : "public.url"
    provider.loadItem(forTypeIdentifier: type, options: nil) { [weak self] item, _ in
      DispatchQueue.main.async {
        if let text = item as? String {
          self?.presentShare(text: text)
        } else if let url = item as? URL {
          self?.presentShare(text: url.absoluteString)
        } else {
          self?.extensionContext?.cancelRequest(withError: NSError(domain: "SupaNotesShare", code: 2))
        }
      }
    }
  }

  private func presentShare(text: String) {
    let view = ShareView(notes: store.notes()) { [weak self] _ in
      self?.store.savePending(text: text)
      self?.extensionContext?.completeRequest(returningItems: nil)
    }
    let host = UIHostingController(rootView: view)
    addChild(host)
    host.view.frame = self.view.bounds
    host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    self.view.addSubview(host.view)
    host.didMove(toParent: self)
  }
}
