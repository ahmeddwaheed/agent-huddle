import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = HuddleStore()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()
    private var hotKey: HotKey?
    private var keyMonitor: Any?
    private var notifier: Notifier?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.imagePosition = .imageLeading

        let snapshotMode = ProcessInfo.processInfo.environment["HUDDLE_SNAPSHOT"] != nil
        let host = NSHostingController(rootView: HuddleRoot(solidBackground: snapshotMode).environmentObject(store))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = false
        popover.appearance = NSAppearance(named: .darkAqua)

        store.closePopover = { [weak self] in self?.popover.performClose(nil) }
        store.onNewRequest = { [weak self] request in self?.showAttention(for: request) }
        notifier = Notifier(store: store) { [weak self] sessionId in self?.openFromNotification(sessionId: sessionId) }
        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateButton()
                self?.notifier?.removeAnswered()
            }
            .store(in: &cancellables)
        updateButton()

        hotKey = HotKey(keyCode: kVK_ANSI_A, modifiers: controlKey | optionKey) { [weak self] in
            DispatchQueue.main.async { self?.hotKeyPressed() }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event) ? nil : event
        }

        if let keys = ProcessInfo.processInfo.environment["HUDDLE_TEST_KEYS"] {
            guard let testSession = ProcessInfo.processInfo.environment["HUDDLE_TEST_SESSION"] else {
                fatalError("HUDDLE_TEST_KEYS needs HUDDLE_TEST_SESSION, so test keys never touch a real request")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self else { return }
                self.store.selectedId = testSession
                for key in keys.split(separator: ",") {
                    guard self.store.activeRequest?.sessionId == testSession else { break }
                    _ = self.store.handleKey(String(key))
                }
            }
        }

        if let path = ProcessInfo.processInfo.environment["HUDDLE_SNAPSHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                if ProcessInfo.processInfo.environment["HUDDLE_DETAIL"] != nil {
                    self?.store.selectedId = self?.store.visibleSessions.first?.id
                }
                guard let self, let button = self.statusItem.button else { return }
                self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.snapshot(to: path) }
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

    private func openFromNotification(sessionId: String) {
        guard NSMenu.menuBarVisible(), let button = statusItem.button else {
            if let session = store.session(sessionId) { store.jump(to: session) }
            return
        }
        store.selectedId = sessionId
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        focusPopover()
    }

    private func showAttention(for request: PendingRequest) {
        if !NSMenu.menuBarVisible() {
            notifier?.notify(request)
        }
        if popover.isShown {
            let current = store.selectedId.flatMap { store.pendingRequest(for: $0) }
            if current == nil { store.selectedId = request.sessionId }
            return
        }
        store.selectedId = request.sessionId
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeFirstResponder(nil)
        if let path = ProcessInfo.processInfo.environment["HUDDLE_ATTENTION_SNAPSHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.snapshot(to: path) }
        }
    }

    private func hotKeyPressed() {
        guard popover.isShown else { return togglePopover() }
        if NSApp.isActive, popover.contentViewController?.view.window?.isKeyWindow == true {
            popover.performClose(nil)
        } else {
            focusPopover()
        }
    }

    private func focusPopover() {
        NSApp.activate()
        guard let window = popover.contentViewController?.view.window else { return }
        window.makeKey()
        DispatchQueue.main.async { window.makeFirstResponder(nil) }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard popover.isShown, event.window === popover.contentViewController?.view.window else { return false }
        if event.keyCode == UInt16(kVK_Escape) {
            if let textView = event.window?.firstResponder as? NSTextView, !textView.string.isEmpty {
                return false
            }
            popover.performClose(nil)
            return true
        }
        if event.window?.firstResponder is NSTextView { return false }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        guard modifiers.isEmpty else { return false }
        let named: [Int: String] = [kVK_Return: "return", kVK_ANSI_KeypadEnter: "return", kVK_LeftArrow: "left", kVK_RightArrow: "right"]
        let key = named[Int(event.keyCode)] ?? (event.charactersIgnoringModifiers ?? "").lowercased()
        return store.handleKey(key)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            if store.selectedId == nil, let request = store.activeRequest {
                store.selectedId = request.sessionId
            }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            focusPopover()
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
