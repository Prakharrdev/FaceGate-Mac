import SwiftUI

/// Main entry point for FaceGuard.
/// Runs as a menu bar app with a shield icon.
@main
struct FaceGuardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @AppStorage(FGConstants.setupCompletedKey) private var setupCompleted = false
    @State private var showSetup = false

    var body: some Scene {
        // Menu bar extra — the primary UI.
        MenuBarExtra {
            MenuBarView()
        } label: {
            Image(systemName: FGConstants.menuBarIcon)
        }
        .menuBarExtraStyle(.window)

        // Setup window — shown on first launch.
        WindowGroup("FaceGuard Setup", id: "setup") {
            SetupView {
                showSetup = false
                AppMonitor.shared.startMonitoring()
            }
        }
        .defaultSize(width: 520, height: 480)
        .windowResizability(.contentSize)
    }
}
