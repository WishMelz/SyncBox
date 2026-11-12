#if os(macOS)
import AppKit
import Observation
import SwiftUI

/// One sync owner for the application, independent of the two visible surfaces.
@MainActor
final class MacDesktopController: NSObject, NSApplicationDelegate {
    private var connection: ConnectionModel?
    private weak var syncingWorkspace: WorkspaceModel?
    private var syncTask: Task<Void, Never>?
    private var sleeping = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose), name: NSWindow.willCloseNotification, object: nil)
    }

    func configure(_ connection: ConnectionModel) {
        guard self.connection == nil else { return }
        self.connection = connection
        observeSession()
        updateSync()
    }

    private func observeSession() {
        withObservationTracking {
            _ = connection?.workspace
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateSync()
                self?.observeSession()
            }
        }
    }

    private func updateSync() {
        syncTask?.cancel()
        syncingWorkspace?.stopEvents()
        syncingWorkspace = nil
        guard !sleeping, let model = connection?.workspace else { return }
        syncingWorkspace = model
        model.startEvents()
        syncTask = Task { [weak model] in
            while !Task.isCancelled {
                guard let model else { return }
                await model.refresh()
                // SSE delivers changes immediately; this is only a fallback.
                do { try await Task.sleep(for: .seconds(model.realtimeConnected ? 60 : 15)) }
                catch { return }
            }
        }
    }

    @objc private func willSleep(_ notification: Notification) {
        sleeping = true
        updateSync()
    }

    @objc private func didWake(_ notification: Notification) {
        sleeping = false
        updateSync()
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.identifier?.rawValue == "syncbox-main" else { return }
        // Closing the workspace leaves a menu bar utility without a Dock tile.
        DispatchQueue.main.async { NSApp.setActivationPolicy(.accessory) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        syncTask?.cancel()
        syncingWorkspace?.stopEvents()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}

struct MacMainWindowRegistration: NSViewRepresentable {
    final class WindowView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.identifier = NSUserInterfaceItemIdentifier("syncbox-main")
        }
    }
    func makeNSView(context: Context) -> WindowView { WindowView() }
    func updateNSView(_ nsView: WindowView, context: Context) {}
}
#endif
