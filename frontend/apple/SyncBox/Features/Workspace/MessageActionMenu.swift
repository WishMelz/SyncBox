import SwiftUI

struct MessageMenuAction: Identifiable {
    let id: String
    let title: String
    let symbol: String
    var destructive = false
    let perform: () -> Void
}

#if os(macOS)
import AppKit

/// Handles secondary clicks before selectable text supplies its editing menu.
/// Ordinary clicks pass through to text selection, links and attachment buttons.
struct MessageSecondaryClickMenu: NSViewRepresentable {
    let actions: [MessageMenuAction]
    let disabled: Bool

    func makeNSView(context: Context) -> MenuView { MenuView() }

    func updateNSView(_ view: MenuView, context: Context) {
        view.actions = actions
        view.disabled = disabled
    }

    final class MenuView: NSView {
        var actions: [MessageMenuAction] = []
        var disabled = false

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent,
                  event.type == .rightMouseDown ||
                    (event.type == .leftMouseDown && event.modifierFlags.contains(.control)),
                  !isHiddenOrHasHiddenAncestor,
                  visibleRect.contains(convert(point, from: superview)) else { return nil }
            return self
        }

        override func rightMouseDown(with event: NSEvent) { showMenu(event) }
        override func mouseDown(with event: NSEvent) { showMenu(event) }

        private func showMenu(_ event: NSEvent) {
            let menu = NSMenu()
            menu.autoenablesItems = false
            for (index, action) in actions.enumerated() {
                let item = NSMenuItem(title: action.title, action: #selector(performAction(_:)), keyEquivalent: "")
                item.target = self
                item.tag = index
                item.isEnabled = !disabled
                item.image = NSImage(systemSymbolName: action.symbol, accessibilityDescription: nil)
                menu.addItem(item)
            }
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }

        @objc private func performAction(_ item: NSMenuItem) {
            guard !disabled, actions.indices.contains(item.tag) else { return }
            actions[item.tag].perform()
        }
    }
}
#endif
