import AppKit
import Testing
@testable import Snap

@MainActor
@Test func nativeDragEventsProduceTheSelectedRectangle() throws {
    _ = NSApplication.shared
    let screen = try #require(NSScreen.main)
    let context = try #require(CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let image = try #require(context.makeImage())
    let overlay = SelectionOverlay(snapshot: DisplaySnapshot(screen: screen, image: image), windows: [])
    let panel = CapturePanel(screen: screen, view: overlay)
    defer { panel.close() }
    var received: CGRect?
    overlay.onCapture = { choice in
        if case let .selection(_, rect) = choice { received = rect }
    }
    func event(_ type: NSEvent.EventType, point: CGPoint) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 1,
            windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    }
    overlay.mouseDown(with: try event(.leftMouseDown, point: CGPoint(x: 400, y: 300)))
    overlay.mouseDragged(with: try event(.leftMouseDragged, point: CGPoint(x: 100, y: 500)))
    overlay.mouseUp(with: try event(.leftMouseUp, point: CGPoint(x: 100, y: 500)))
    #expect(received?.width == 300)
    #expect(received?.height == 200)
    #expect(received?.minX == 100)
    #expect(received?.minY == screen.frame.height - 500)
}

@MainActor
@Test func clickingWithoutDraggingDoesNotSaveAnImage() throws {
    _ = NSApplication.shared
    let screen = try #require(NSScreen.main)
    let context = try #require(CGContext(data: nil, width: 10, height: 10, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let image = try #require(context.makeImage())
    let overlay = SelectionOverlay(snapshot: DisplaySnapshot(screen: screen, image: image), windows: [])
    let panel = CapturePanel(screen: screen, view: overlay)
    defer { panel.close() }
    var captured = false
    overlay.onCapture = { _ in captured = true }
    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
        let event = try #require(NSEvent.mouseEvent(with: type, location: CGPoint(x: 50, y: 50),
            modifierFlags: [], timestamp: 1, windowNumber: panel.windowNumber, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1))
        if type == .leftMouseDown { overlay.mouseDown(with: event) }
        else { overlay.mouseUp(with: event) }
    }
    #expect(!captured)
}
