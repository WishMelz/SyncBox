#if os(macOS)
import AppKit
import Observation
import SwiftUI

/// One sync owner for the application, independent of the two visible surfaces.
@MainActor
final class MacDesktopController: NSObject, NSApplicationDelegate {
    private var connection: ConnectionModel?
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private weak var syncingWorkspace: WorkspaceModel?
    private var syncTask: Task<Void, Never>?
    private var sleeping = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        installStatusItem()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose), name: NSWindow.willCloseNotification, object: nil)
    }

    func configure(_ connection: ConnectionModel) {
        guard self.connection == nil else { return }
        self.connection = connection
        installPopover(for: connection)
        observeSession()
        updateSync()
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = item.button else { return }
        if let image = NSImage(named: "BrandIcon") {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = false
            button.image = image
        }
        button.imageScaling = .scaleProportionallyDown
        button.imagePosition = .imageOnly
        button.toolTip = "SyncBox"
        button.target = self
        button.action = #selector(togglePopover(_:))
        statusItem = item
    }

    private func installPopover(for connection: ConnectionModel) {
        let panel = MacQuickPanel(connection: connection) { [weak self] in
            self?.showMainWindow()
        }
        let hosting = NSHostingController(rootView: panel.tint(ChatStyle.blue))
        let popover = NSPopover()
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 380, height: 560)
        self.popover = popover
        applyPopoverAppearance()
    }

    private func applyPopoverAppearance() {
        guard let popover else { return }
        let appearance = NSApp.mainWindow?.effectiveAppearance ?? NSApp.effectiveAppearance
        popover.appearance = appearance
        popover.contentViewController?.view.appearance = appearance
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            applyPopoverAppearance()
            NSApp.setActivationPolicy(.accessory)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func showMainWindow() {
        popover?.performClose(nil)
        NSApp.setActivationPolicy(.regular)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "syncbox-main" }) {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
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
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
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
