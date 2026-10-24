import AppKit
import ShareXMacCore

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let onAction: (HotkeyAction) -> Void
    private var captureItems: [NSMenuItem] = []

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
        add("History…", action: .history, to: menu)
        add("Image History…", action: .imageHistory, to: menu)
        menu.addItem(.separator())
        add("Settings…", action: .settings, to: menu)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit ShareX Mac", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        statusItem.menu = menu
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
        if capture { captureItems.append(item) }
    }

    @objc private func performAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = HotkeyAction(rawValue: raw) else { return }
        onAction(action)
    }
}
