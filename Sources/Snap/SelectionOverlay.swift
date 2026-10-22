import AppKit
import SnapCore

enum CaptureChoice {
    case selection(DisplaySnapshot, CGRect)
    case window(DisplaySnapshot, WindowRegion)
    case display(DisplaySnapshot)
}

@MainActor
final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(screen: NSScreen, view: NSView) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        hidesOnDeactivate = false
        animationBehavior = .none
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        contentView = view
        setFrame(screen.frame, display: true)
    }
}

@MainActor
final class SelectionOverlay: NSView {
    let snapshot: DisplaySnapshot
    let windows: [WindowRegion]
    private(set) var regions: [WindowRegion] = []
    var onCapture: ((CaptureChoice) -> Void)?
    var onActive: ((SelectionOverlay) -> Void)?
    var onStateChanged: (() -> Void)?
    private var tracking: NSTrackingArea?
    private var start: CGPoint?
    private(set) var selection: CGRect?
    private(set) var hoveredRegion: WindowRegion?
    private var keyboardTarget = false
    private var regionDetectionFinished = false
    var savesToFile = false {
        didSet { updateAccessibilityState() }
    }
    var mode: CaptureMode = .select {
        didSet {
            start = nil
            selection = nil
            updateAccessibilityState()
            updateHover()
            window?.invalidateCursorRects(for: self)
            refreshCursor()
            needsDisplay = true
        }
    }
    private let backgroundImage: NSImage

    init(snapshot: DisplaySnapshot, windows: [WindowRegion]) {
        self.snapshot = snapshot
        self.windows = windows
        backgroundImage = NSImage(cgImage: snapshot.image, size: snapshot.screen.frame.size)
        super.init(frame: CGRect(origin: .zero, size: snapshot.screen.frame.size))
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Screenshot canvas")
        updateAccessibilityState()
        setAccessibilityHelp("Drag in Select. Region selects sections within an app. App selects a whole window. Left and right arrows change modes. Tab selects another Region or App target, Return captures, Up toggles file saving, and Escape cancels.")
    }

    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private func updateAccessibilityState() {
        let target = (mode == .region || mode == .app) ? hoveredRegion.map {
            ", \($0.title), \(Int($0.frame.width)) by \(Int($0.frame.height)) points"
        } ?? "" : ""
        let detection = mode == .region && !regionDetectionFinished ? ", finding sections" : ""
        setAccessibilityValue("\(mode.title)\(target)\(detection), file saving \(savesToFile ? "on" : "off")")
    }

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .cursorUpdate,
                      .inVisibleRect, .enabledDuringMouseDrag], owner: self)
        tracking = area
        addTrackingArea(area)
        super.updateTrackingAreas()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: captureCursor)
    }

    private var captureCursor: NSCursor { mode == .region || mode == .app ? .pointingHand : .crosshair }

    override func cursorUpdate(with event: NSEvent) {
        captureCursor.set()
    }

    func refreshCursor() {
        // A keyboard mode change must not replace the toolbar's cursor or another display's cursor.
        guard let window, window.isVisible,
              NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0)
                == window.windowNumber else { return }
        captureCursor.set()
    }

    override func mouseEntered(with event: NSEvent) { activateAndHover(at: globalPoint(event)) }
    override func mouseMoved(with event: NSEvent) { activateAndHover(at: globalPoint(event)) }

    private func activateAndHover(at point: CGPoint) {
        onActive?(self)
        captureCursor.set()
        updateHover(at: point)
    }

    func setDetectedRegions(_ regions: [WindowRegion]) {
        self.regions = regions
        regionDetectionFinished = true
        if mode == .region && !keyboardTarget { updateHover() }
        else { updateAccessibilityState() }
    }

    func updateHover(at point: CGPoint = NSEvent.mouseLocation) {
        keyboardTarget = false
        // Find the frontmost window first, so a small section in a covered app never wins.
        if let window = windows.first(where: { $0.frame.contains(point) }) {
            hoveredRegion = mode == .region ? regions.filter {
                $0.id == window.id && $0.frame.contains(point)
            }.min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height } ?? window : window
        } else { hoveredRegion = nil }
        updateAccessibilityState()
        needsDisplay = true
        onStateChanged?()
    }

    func cycleRegion(_ direction: Int) {
        let available = windows.flatMap { window in
            mode == .region ? regions.filter { $0.id == window.id } + [window] : [window]
        }.filter { $0.frame.intersects(snapshot.screen.frame) }
        guard !available.isEmpty else { return }
        let index = hoveredRegion.flatMap { current in available.firstIndex(of: current) }
        let next = index.map { ($0 + direction + available.count) % available.count } ?? 0
        hoveredRegion = available[next]
        keyboardTarget = true
        updateAccessibilityState()
        needsDisplay = true
        onStateChanged?()
    }

    override func mouseDown(with event: NSEvent) {
        onActive?(self)
        captureCursor.set()
        switch mode {
        case .select:
            start = localPoint(event)
            selection = nil
        case .region, .app:
            updateHover(at: globalPoint(event))
        case .fullScreen: break
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard mode == .select, let start else { return }
        captureCursor.set()
        selection = CaptureGeometry.rectangle(from: start, to: localPoint(event))
        needsDisplay = true
        onStateChanged?()
    }

    override func mouseUp(with event: NSEvent) {
        if mode == .select, let start {
            selection = CaptureGeometry.rectangle(from: start, to: localPoint(event))
            self.start = nil
        }
        capture()
    }

    func capture() {
        switch mode {
        case .select:
            guard let selection, selection.width >= 2, selection.height >= 2 else { return }
            onCapture?(.selection(snapshot, selection))
        case .region, .app:
            guard let hoveredRegion else { NSSound.beep(); return }
            onCapture?(.window(snapshot, hoveredRegion))
        case .fullScreen:
            onCapture?(.display(snapshot))
        }
    }

    private func localPoint(_ event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: min(max(point.x, 0), bounds.width), y: min(max(point.y, 0), bounds.height))
    }

    private func globalPoint(_ event: NSEvent) -> CGPoint {
        let point = localPoint(event)
        return CGPoint(x: snapshot.screen.frame.minX + point.x, y: snapshot.screen.frame.maxY - point.y)
    }

    var highlightedRect: CGRect? {
        switch mode {
        case .select: selection
        case .region, .app: hoveredRegion.map { CaptureGeometry.localTopLeft($0.frame, screen: snapshot.screen.frame) }
        case .fullScreen: bounds
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        backgroundImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        guard let rawRect = highlightedRect else { return }
        let rect = rawRect.intersection(bounds)
        guard !rect.isNull, rect.width > 0, rect.height > 0 else { return }
        NSColor.black.withAlphaComponent(0.55).setStroke()
        let outer = NSBezierPath(rect: rect.insetBy(dx: -0.5, dy: -0.5))
        outer.lineWidth = 3
        outer.stroke()
        NSColor.white.setStroke()
        let edge = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        edge.lineWidth = 1
        edge.stroke()

        if mode == .select {
            let scale = snapshot.screen.backingScaleFactor
            let text = "\(Int((rect.width * scale).rounded())) × \(Int((rect.height * scale).rounded()))"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white]
            let size = (text as NSString).size(withAttributes: attributes)
            let label = CGRect(x: min(max(rect.midX - size.width / 2 - 8, 8), bounds.width - size.width - 24),
                               y: max(8, rect.minY - 31), width: size.width + 16, height: 24)
            NSColor.black.withAlphaComponent(0.85).setFill()
            NSBezierPath(roundedRect: label, xRadius: 5, yRadius: 5).fill()
            (text as NSString).draw(at: CGPoint(x: label.minX + 8, y: label.minY + 4), withAttributes: attributes)
        }
    }
}

@MainActor
final class CaptureToolbar: NSPanel {
    var onMode: ((CaptureMode) -> Void)?
    var onCancel: (() -> Void)?
    var onSaveToggle: (() -> Void)?
    private let segments: NSSegmentedControl
    private let saveButton = NSButton(checkboxWithTitle: "Desktop", target: nil, action: nil)

    override var canBecomeKey: Bool { true }

    init() {
        segments = NSSegmentedControl(labels: CaptureMode.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
        super.init(contentRect: CGRect(x: 0, y: 0, width: 360, height: 44), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        title = "Snap Capture"
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        animationBehavior = .none
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        appearance = NSAppearance(named: .darkAqua)

        let material = NSVisualEffectView(frame: CGRect(x: 0, y: 0, width: 360, height: 44))
        material.material = .hudWindow
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = 10
        material.layer?.masksToBounds = true
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            material.state = .inactive
            material.layer?.backgroundColor = NSColor(white: 0.13, alpha: 1).cgColor
        }
        contentView = material

        segments.selectedSegment = 0
        segments.segmentStyle = .rounded
        segments.controlSize = .small
        segments.target = self
        segments.action = #selector(modeChanged)
        segments.setAccessibilityLabel("Capture mode")
        segments.toolTip = "Left and right arrows cycle capture modes"
        for (index, text) in ["Drag a rectangle (1)", "Select a section within an app (2)",
                              "Select a whole app window (3)", "Capture the current display (4)"].enumerated() {
            segments.setToolTip(text, forSegment: index)
        }
        saveButton.controlSize = .small
        saveButton.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        saveButton.contentTintColor = .white
        saveButton.state = .off
        saveButton.cell?.lineBreakMode = .byTruncatingMiddle
        saveButton.widthAnchor.constraint(equalToConstant: 88).isActive = true
        saveButton.toolTip = "Save to Desktop (↑)"
        saveButton.target = self
        saveButton.action = #selector(saveToggled)
        saveButton.setAccessibilityLabel("Save to Desktop")
        let cancel = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Cancel screenshot") ?? NSImage(), target: self, action: #selector(cancelPressed))
        cancel.isBordered = false
        cancel.contentTintColor = .white
        cancel.toolTip = "Cancel (Esc)"
        cancel.setAccessibilityLabel("Cancel screenshot")
        cancel.widthAnchor.constraint(equalToConstant: 28).isActive = true
        cancel.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let row = NSStackView(views: [segments, saveButton, cancel])
        row.spacing = 8
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(row)
        NSLayoutConstraint.activate([
            row.centerXAnchor.constraint(equalTo: material.centerXAnchor),
            row.centerYAnchor.constraint(equalTo: material.centerYAnchor),
            row.leadingAnchor.constraint(greaterThanOrEqualTo: material.leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(lessThanOrEqualTo: material.trailingAnchor, constant: -10)
        ])
        setContentSize(NSSize(width: row.fittingSize.width + 20, height: 44))
        update(mode: .select, savesToFile: false, directory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop"))
    }

    func update(mode: CaptureMode, savesToFile: Bool, directory: URL) {
        segments.selectedSegment = mode.rawValue
        saveButton.state = savesToFile ? .on : .off
        saveButton.title = directory.lastPathComponent
        saveButton.toolTip = "Save to \(directory.path) (↑)"
        saveButton.setAccessibilityLabel("Save to \(directory.lastPathComponent)")
    }

    func position(on screen: NSScreen) {
        let area = screen.visibleFrame
        setFrameOrigin(CGPoint(x: area.midX - frame.width / 2, y: area.minY + 20))
    }

    @objc private func modeChanged() { onMode?(CaptureMode(rawValue: segments.selectedSegment) ?? .select) }
    @objc private func cancelPressed() { onCancel?() }
    @objc private func saveToggled() { onSaveToggle?() }
}
