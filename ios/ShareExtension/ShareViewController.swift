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
          let provider = item.attachments?.first,
          provider.hasItemConformingToTypeIdentifier("public.plain-text")
    else {
      extensionContext?.cancelRequest(withError: NSError(domain: "SupaNotesShare", code: 1))
      return
    }
    provider.loadItem(forTypeIdentifier: "public.plain-text", options: nil) { [weak self] item, _ in
      DispatchQueue.main.async {
        if let text = item as? String {
          self?.presentShare(text: text)
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
