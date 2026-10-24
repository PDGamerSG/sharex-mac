import AppKit
import ShareXMacCore

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let onAction: (HotkeyAction) -> Void
    private var captureItems: [NSMenuItem] = []
    private var actionItems: [HotkeyAction: NSMenuItem] = [:]
    private var baseTitles: [HotkeyAction: String] = [:]

    init(onAction: @escaping (HotkeyAction) -> Void) {
        self.onAction = onAction
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "ShareX Mac")
        statusItem.button?.toolTip = "ShareX Mac"
        let menu = NSMenu()
        menu.autoenablesItems = false
        add("Capture All Displays", action: .fullscreen, to: menu, capture: true)
        add("Capture Region…", action: .region, to: menu, capture: true)
        add("Capture Window…", action: .window, to: menu, capture: true)
        menu.addItem(.separator())
        add("Recognize Text in Region…", action: .ocrRegion, to: menu, capture: true)
        menu.addItem(.separator())
        add("Image History…", action: .imageHistory, to: menu)
        menu.addItem(.separator())
        add("Settings…", action: .settings, to: menu)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit ShareX Mac", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        statusItem.menu = menu
    }

    func updateShortcuts(_ bindings: [HotkeyAction: HotkeyBinding]) {
        for (action, item) in actionItems {
            guard let title = baseTitles[action] else { continue }
            let binding = bindings[action]
            item.title = if let binding, !binding.isEmpty {
                "\(title)  —  \(binding.displayName)"
            } else {
                title
            }
            item.toolTip = binding.map { $0.isEmpty ? title : "Shortcut: \($0.displayName)" } ?? title
        }
    }

    func setCapturing(_ busy: Bool) {
        captureItems.forEach { $0.isEnabled = !busy }
        statusItem.button?.toolTip = busy ? "ShareX Mac — capture in progress" : "ShareX Mac"
    }

    private func add(_ title: String, action: HotkeyAction, to menu: NSMenu, capture: Bool = false) {
        let item = NSMenuItem(title: title, action: #selector(performAction(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = action.rawValue
        menu.addItem(item)
        actionItems[action] = item
        baseTitles[action] = title
        if capture { captureItems.append(item) }
    }

    @objc private func performAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = HotkeyAction(rawValue: raw) else { return }
        onAction(action)
    }
}
