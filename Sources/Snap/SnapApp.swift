import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SnapCore
import OSLog

@main
@MainActor
enum SnapMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = SnapDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class SnapDelegate: NSObject, NSApplicationDelegate {
    enum Phase { case idle, preparing, selecting, saving }
    private var phase = Phase.idle
    private let engine = CaptureEngine()
    private let regionDetector = RegionDetector()
    private let store = ScreenshotStore()
    private var statusItem: NSStatusItem?
    private var settingsPopover: NSPopover?
    private var shortcut: GlobalShortcut?
    private var captureTask: Task<Void, Never>?
    private var regionTask: Task<Void, Never>?
    private var receiptTask: Task<Void, Never>?
    private var session = UUID()
    private var panels: [CapturePanel] = []
    private var overlays: [SelectionOverlay] = []
    private var activeOverlay: SelectionOverlay?
    private var toolbar: CaptureToolbar?
    private var keyMonitor: Any?
    private var permissionWindow: NSWindow?
    private var receiptWindow: NSPanel?
    private var mode = CaptureMode.select
    private var savesToFile = false
    private var lastFile: URL?
    private var requestedPermission = false
    private var hotkeyAvailable = true

    private var saveDirectory: URL {
        if let path = UserDefaults.standard.string(forKey: "saveDirectory") {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        if let button = item.button {
            button.image = SnapIcon.menuBarImage()
            button.toolTip = "Snap — settings and capture (⌘⇧S)"
            button.setAccessibilityLabel("Snap settings and capture")
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        let shortcut = GlobalShortcut { [weak self] in self?.beginCapture() }
        self.shortcut = shortcut
        hotkeyAvailable = shortcut.register()
        if !ProcessInfo.processInfo.arguments.contains("--menu-only") { showSettings() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        captureTask?.cancel()
        regionTask?.cancel()
        receiptTask?.cancel()
        shortcut?.unregister()
        settingsPopover?.performClose(nil)
        closeCaptureUI()
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp, let button = statusItem?.button {
            statusItem?.menu = makeMenu()
            button.performClick(nil)
            statusItem?.menu = nil
        } else {
            if settingsPopover?.isShown == true { settingsPopover?.performClose(nil) }
            else { showSettings() }
        }
    }

    @objc private func showSettings() {
        guard phase == .idle, let button = statusItem?.button else { return }
        let view = SettingsPopoverView(directory: saveDirectory,
            screenAccess: CGPreflightScreenCaptureAccess(), hotkeyAvailable: hotkeyAvailable,
            capture: { [weak self] in self?.beginCapture() },
            chooseFolder: { [weak self] in
                self?.settingsPopover?.performClose(nil)
                self?.chooseFolder()
            },
            openFolder: { [weak self] in
                self?.settingsPopover?.performClose(nil)
                self?.openFolder()
            },
            permissions: { [weak self] in
                self?.settingsPopover?.performClose(nil)
                self?.openPermissions()
            },
            quit: { [weak self] in self?.quit() })
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        let host = NSHostingController(rootView: view)
        popover.contentViewController = host
        popover.contentSize = host.view.fittingSize
        settingsPopover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let capture = NSMenuItem(title: "Take Screenshot", action: #selector(captureFromMenu), keyEquivalent: "s")
        capture.keyEquivalentModifierMask = [.command, .shift]
        capture.target = self
        menu.addItem(capture)
        addMenuItem("Settings…", action: #selector(showSettings), key: ",", to: menu)
        if !hotkeyAvailable {
            let warning = NSMenuItem(title: "⌘⇧S is in use by another app", action: nil, keyEquivalent: "")
            warning.isEnabled = false
            menu.addItem(warning)
        }
        menu.addItem(.separator())
        addMenuItem("Open Screenshots Folder", action: #selector(openFolder), to: menu)
        addMenuItem("Choose Save Folder…", action: #selector(chooseFolder), to: menu)
        if lastFile != nil { addMenuItem("Show Last Screenshot", action: #selector(showLastFile), to: menu) }
        if !CGPreflightScreenCaptureAccess() {
            addMenuItem("Allow Screen Recording…", action: #selector(openPermissions), to: menu)
        }
        menu.addItem(.separator())
        addMenuItem("Quit Snap", action: #selector(quit), key: "q", to: menu)
        return menu
    }

    private func addMenuItem(_ title: String, action: Selector, key: String = "", to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    @objc private func captureFromMenu() { beginCapture() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func openFolder() { NSWorkspace.shared.open(saveDirectory) }
    @objc private func showLastFile() {
        if let lastFile { NSWorkspace.shared.activateFileViewerSelecting([lastFile]) }
    }

    @objc private func chooseFolder() {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.title = "Save Snap Screenshots"
        panel.prompt = "Choose Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = saveDirectory
        if panel.runModal() == .OK, let directory = panel.url {
            UserDefaults.standard.set(directory.path, forKey: "saveDirectory")
        }
    }

    func beginCapture() {
        settingsPopover?.performClose(nil)
        guard phase == .idle else {
            if phase == .selecting || phase == .preparing { cancelCapture() }
            return
        }
        dismissReceipt()
        guard CGPreflightScreenCaptureAccess() else {
            showPermissionWindow()
            if !requestedPermission {
                requestedPermission = true
                if CGRequestScreenCaptureAccess() {
                    permissionWindow?.close()
                    beginCapture()
                }
            }
            return
        }
        permissionWindow?.close()
        phase = .preparing
        let token = UUID()
        session = token
        installKeyMonitor()
        captureTask = Task { [weak self] in
            guard let self else { return }
            do {
                // Freeze before drawing any capture controls.
                // The content filter excludes Snap's own windows, so no delay is needed.
                let snapshots = try await self.engine.snapshots()
                try Task.checkCancellation()
                guard self.session == token else { return }
                self.presentCapture(snapshots)
                self.captureTask = nil
            } catch is CancellationError {
                if self.session == token { self.resetSession() }
            } catch {
                guard self.session == token else { return }
                self.resetSession()
                if !CGPreflightScreenCaptureAccess() { self.showPermissionWindow() }
                else { self.showError("Couldn’t capture the screen", error.localizedDescription) }
            }
        }
    }

    private func presentCapture(_ snapshots: [DisplaySnapshot]) {
        let windows = engine.windowRegions()
        mode = .select
        savesToFile = false
        for snapshot in snapshots {
            let overlay = SelectionOverlay(snapshot: snapshot, windows: windows)
            overlay.onCapture = { [weak self] choice in self?.finishCapture(choice) }
            overlay.onActive = { [weak self] overlay in self?.activateOverlay(overlay) }
            overlay.onStateChanged = { [weak self] in self?.refreshToolbar() }
            let panel = CapturePanel(screen: snapshot.screen, view: overlay)
            overlays.append(overlay)
            panels.append(panel)
            panel.orderFrontRegardless()
        }
        let toolbar = CaptureToolbar()
        toolbar.onMode = { [weak self] mode in self?.setMode(mode) }
        toolbar.onCancel = { [weak self] in self?.cancelCapture() }
        toolbar.onSaveToggle = { [weak self] in self?.toggleSaving() }
        self.toolbar = toolbar
        phase = .selecting
        // Nonactivating panels take keyboard focus without changing the active app or Space.
        let active = overlays.first { $0.snapshot.screen.frame.contains(NSEvent.mouseLocation) } ?? overlays.first
        if let active { activateOverlay(active) }
        toolbar.orderFrontRegardless()
        active?.refreshCursor()
        detectRegions(windows: windows)
    }

    private func detectRegions(windows: [WindowRegion]) {
        let token = session
        let canvases = overlays
        regionTask = Task { [weak self] in
            guard let self else { return }
            for overlay in canvases {
                do {
                    let regions = try await self.regionDetector.regions(in: overlay.snapshot.image,
                        screen: overlay.snapshot.screen.frame, windows: windows)
                    try Task.checkCancellation()
                    guard self.session == token, self.phase == .selecting else { return }
                    overlay.setDetectedRegions(regions)
                } catch is CancellationError { return }
                catch {
                    guard !Task.isCancelled, self.session == token, self.phase == .selecting else { return }
                    Logger(subsystem: "dev.matthew.snap", category: "regions")
                        .error("Section detection failed; whole-window capture remains available: \(error.localizedDescription, privacy: .public)")
                    overlay.setDetectedRegions([])
                }
            }
            if self.session == token { self.regionTask = nil }
        }
    }

    private func activateOverlay(_ overlay: SelectionOverlay) {
        guard phase == .selecting else { return }
        if activeOverlay !== overlay {
            activeOverlay = overlay
            overlay.window?.makeKey()
            overlay.window?.makeFirstResponder(overlay)
            toolbar?.position(on: overlay.snapshot.screen)
        }
        refreshToolbar()
    }

    private func refreshToolbar() {
        toolbar?.update(mode: mode, savesToFile: savesToFile, directory: saveDirectory)
    }

    private func toggleSaving() {
        guard phase == .selecting else { return }
        savesToFile.toggle()
        for overlay in overlays { overlay.savesToFile = savesToFile }
        refreshToolbar()
    }

    private func setMode(_ next: CaptureMode) {
        guard phase == .selecting else { return }
        mode = next
        for overlay in overlays { overlay.mode = next }
        refreshToolbar()
    }

    private func installKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { self.cancelCapture(); return nil }
            guard self.phase == .selecting, !event.modifierFlags.contains(.command) else { return event }
            switch event.keyCode {
            case 123: self.setMode(self.mode.stepping(-1))
            case 124: self.setMode(self.mode.stepping(1))
            case 126: self.toggleSaving()
            case 18: self.setMode(.select)
            case 19: self.setMode(.region)
            case 20: self.setMode(.app)
            case 21: self.setMode(.fullScreen)
            case 36, 76: self.activeOverlay?.capture()
            case 48:
                guard self.mode == .region || self.mode == .app else { return event }
                self.activeOverlay?.cycleRegion(event.modifierFlags.contains(.shift) ? -1 : 1)
            default: return event
            }
            return nil
        }
    }

    private func cancelCapture() {
        session = UUID()
        captureTask?.cancel()
        captureTask = nil
        resetSession()
    }

    private func closeCaptureUI() {
        regionTask?.cancel()
        regionTask = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        toolbar?.orderOut(nil)
        toolbar?.close()
        toolbar = nil
        for panel in panels { panel.orderOut(nil); panel.close() }
        panels.removeAll()
        overlays.removeAll()
        activeOverlay = nil
    }

    private func resetSession() {
        closeCaptureUI()
        phase = .idle
    }

    private func finishCapture(_ choice: CaptureChoice) {
        guard phase == .selecting else { return }
        phase = .saving
        let shouldSave = savesToFile
        let directory = saveDirectory
        let screen = activeOverlay?.snapshot.screen ?? NSScreen.main
        closeCaptureUI()
        let token = session
        captureTask = Task { [weak self] in
            guard let self else { return }
            defer { self.phase = .idle; self.captureTask = nil }
            do {
                let image: CGImage
                switch choice {
                case let .selection(snapshot, rect):
                    image = try snapshot.cropped(to: rect)
                case let .window(snapshot, region):
                    image = try snapshot.cropped(to: CaptureGeometry.localTopLeft(region.frame, screen: snapshot.screen.frame))
                case let .display(snapshot): image = snapshot.image
                }
                try Task.checkCancellation()
                let data = try await self.store.encode(image)
                try Task.checkCancellation()
                guard self.session == token else { return }
                NSPasteboard.general.clearContents()
                let copied = NSPasteboard.general.setData(data, forType: .png)
                let file: URL?
                if shouldSave {
                    do { file = try await self.store.save(data, directory: directory) }
                    catch {
                        guard let destination = self.chooseRecoveryLocation(copied: copied, error: error) else { return }
                        try await self.store.saveExactly(data, url: destination)
                        file = destination
                    }
                } else if !copied {
                    guard let destination = self.chooseRecoveryLocation(copied: false, error: SnapError.clipboardFailed) else { return }
                    try await self.store.saveExactly(data, url: destination)
                    file = destination
                } else {
                    file = nil
                }
                if let file { self.lastFile = file }
                self.showReceipt(image: image, file: file, screen: screen, copied: copied)
                if !copied { self.showError("Screenshot saved", "The PNG was saved, but macOS couldn’t copy it to the clipboard. Open the saved image to copy it.") }
            } catch is CancellationError { return }
            catch { self.showError("Couldn’t finish the screenshot", error.localizedDescription) }
        }
    }

    private func chooseRecoveryLocation(copied: Bool, error: Error) -> URL? {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = copied ? "Screenshot copied. Choose where to save it." : "Choose where to save your screenshot."
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "Save As…")
        alert.addButton(withTitle: copied ? "Keep Clipboard Only" : "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Snap.png"
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func showPermissionWindow() {
        if permissionWindow == nil {
            let view = PermissionView(request: { [weak self] in self?.openPermissions() },
                                      retry: { [weak self] in self?.beginCapture() })
            let host = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: host.fittingSize),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Snap"
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.center()
            permissionWindow = window
        }
        NSApp.activate()
        permissionWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openPermissions() {
        if !requestedPermission {
            requestedPermission = true
            _ = CGRequestScreenCaptureAccess()
        }
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    private func showError(_ title: String, _ detail: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showReceipt(image: CGImage, file: URL?, screen: NSScreen?, copied: Bool) {
        dismissReceipt()
        let size = CGSize(width: file == nil ? 216 : 328, height: 74)
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        let receipt = ReceiptView(image: NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height)),
            directory: file?.deletingLastPathComponent().lastPathComponent, copied: copied,
            showFile: { if let file { NSWorkspace.shared.activateFileViewerSelecting([file]) } }, dismiss: { [weak self] in self?.dismissReceipt() })
        let host = NSHostingView(rootView: receipt)
        host.wantsLayer = true
        host.layer?.cornerRadius = 12
        host.layer?.masksToBounds = true
        panel.contentView = host
        if let area = (screen ?? NSScreen.main)?.visibleFrame {
            panel.setFrameOrigin(CGPoint(x: area.maxX - size.width - 20, y: area.minY + 20))
        }
        receiptWindow = panel
        panel.orderFrontRegardless()
        receiptTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(5)) }
            catch { return }
            self?.dismissReceipt()
        }
    }

    private func dismissReceipt() {
        receiptTask?.cancel()
        receiptTask = nil
        receiptWindow?.orderOut(nil)
        receiptWindow?.close()
        receiptWindow = nil
    }
}
