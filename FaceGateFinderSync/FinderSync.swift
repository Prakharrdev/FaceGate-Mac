import FinderSync
import Foundation

final class FaceGateFinderSync: FIFinderSync {
    private let db = MetadataDatabase.shared

    override init() {
        super.init()
        let controller = FIFinderSyncController.default()
        controller.directoryURLs = [
            URL(fileURLWithPath: "\(NSHomeDirectory())/Desktop"),
            URL(fileURLWithPath: "\(NSHomeDirectory())/Documents"),
            URL(fileURLWithPath: "\(NSHomeDirectory())/Downloads"),
        ]
    }

    override func requestBadgeIdentifier(for url: URL) {
        let path = url.path
        let controller = FIFinderSyncController.default()
        if path.hasSuffix(".facegate") && db.fileExists(withCurrentPath: path) {
            controller.setBadgeIdentifier("FaceGateLocked", for: url)
        } else if let _ = db.file(forCurrentPath: path) {
            controller.setBadgeIdentifier("FaceGateLocked", for: url)
        } else {
            controller.setBadgeIdentifier("", for: url)
        }
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu()
        let items = FIFinderSyncController.default().selectedItemURLs() ?? []

        guard let firstItem = items.first else {
            let item = menu.addItem(withTitle: "Protect with FaceGate", action: #selector(protectFiles), keyEquivalent: "")
            item.target = self
            return menu
        }

        let isProtected = firstItem.pathExtension.lowercased() == "facegate" &&
                          db.fileExists(withCurrentPath: firstItem.path)

        if isProtected {
            let openItem = menu.addItem(withTitle: "Open with FaceGate", action: #selector(openFile), keyEquivalent: "")
            openItem.target = self

            let unprotectItem = menu.addItem(withTitle: "Remove Protection", action: #selector(unprotectFile), keyEquivalent: "")
            unprotectItem.target = self

            menu.addItem(.separator())

            let infoItem = menu.addItem(withTitle: "Protected File Info", action: #selector(showFileInfo), keyEquivalent: "")
            infoItem.target = self
        } else {
            let protectItem = menu.addItem(withTitle: "Protect with FaceGate", action: #selector(protectFiles), keyEquivalent: "")
            protectItem.target = self
        }

        return menu
    }

    @objc private func protectFiles() {
        guard let items = FIFinderSyncController.default().selectedItemURLs() else { return }
        for item in items {
            notifyMainApp(action: "protect", path: item.path)
        }
    }

    @objc private func unprotectFile() {
        guard let items = FIFinderSyncController.default().selectedItemURLs(),
              let first = items.first else { return }
        notifyMainApp(action: "unprotect", path: first.path)
    }

    @objc private func openFile() {
        guard let items = FIFinderSyncController.default().selectedItemURLs(),
              let first = items.first else { return }
        notifyMainApp(action: "open", path: first.path)
    }

    @objc private func showFileInfo() {
        guard let items = FIFinderSyncController.default().selectedItemURLs(),
              let first = items.first else { return }
        notifyMainApp(action: "info", path: first.path)
    }

    private func notifyMainApp(action: String, path: String) {
        guard var components = URLComponents(string: "facegate://\(action)") else { return }
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }
}
