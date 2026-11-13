import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = HuddleStore()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.imagePosition = .imageLeading

        let host = NSHostingController(rootView: HuddleRoot().environmentObject(store))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = false
        popover.appearance = NSAppearance(named: .darkAqua)

        store.closePopover = { [weak self] in self?.popover.performClose(nil) }
        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateButton() }
            .store(in: &cancellables)
        updateButton()

        if let path = ProcessInfo.processInfo.environment["HUDDLE_SNAPSHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                if ProcessInfo.processInfo.environment["HUDDLE_DETAIL"] != nil {
                    self?.store.selectedId = self?.store.visibleSessions.first?.id
                }
                self?.togglePopover()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self?.snapshot(to: path) }
            }
        }
    }

    private func snapshot(to path: String) {
        guard let view = popover.contentViewController?.view,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            FileHandle.standardError.write(Data("snapshot failed shown=\(popover.isShown)\n".utf8))
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func updateButton() {
        guard let button = statusItem.button else { return }
        let count = store.visibleSessions.count
        button.image = robotGlyph(alert: store.needsAttention)
        button.title = count > 0 ? " \(count)" : ""
        button.contentTintColor = store.needsAttention ? NSColor(red: 0.85, green: 0.96, blue: 0.36, alpha: 1) : nil
    }

    private func robotGlyph(alert: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in
            NSColor.black.setFill()
            let body = NSBezierPath(roundedRect: NSRect(x: 2, y: 1, width: 12, height: 11), xRadius: 2.5, yRadius: 2.5)
            body.fill()
            NSColor.clear.setFill()
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(rect: NSRect(x: 5, y: 4, width: 1.8, height: 3)).fill()
            NSBezierPath(rect: NSRect(x: 9.2, y: 4, width: 1.8, height: 3)).fill()
            NSBezierPath(rect: NSRect(x: 6, y: 8.6, width: 4, height: 1.2)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.black.setFill()
            NSBezierPath(rect: NSRect(x: 4.5, y: 12, width: 2, height: 3)).fill()
            NSBezierPath(rect: NSRect(x: 9.5, y: 12, width: 2, height: 3)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
