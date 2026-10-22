import AppKit
import SnapCore
import Testing
@testable import Snap

@Suite @MainActor
struct SelectionCursorTests {
    private func makeOverlay() throws -> SelectionOverlay {
        _ = NSApplication.shared
        let screen = try #require(NSScreen.main)
        let context = try #require(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return SelectionOverlay(snapshot: DisplaySnapshot(screen: screen,
            image: try #require(context.makeImage())), windows: [])
    }

    @Test func enteringAndMovingOnTheCanvasReplacesThePreviousAppsCursor() throws {
        let overlay = try makeOverlay()
        let previous = NSCursor.current
        defer { previous.set() }
        let entered = try #require(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero,
            modifierFlags: [], timestamp: 1, windowNumber: 0, context: nil,
            eventNumber: 1, trackingNumber: 0, userData: nil))
        let moved = try #require(NSEvent.mouseEvent(with: .mouseMoved, location: .zero,
            modifierFlags: [], timestamp: 1, windowNumber: 0, context: nil,
            eventNumber: 1, clickCount: 0, pressure: 0))

        NSCursor.iBeam.set()
        overlay.mouseEntered(with: entered)
        #expect(NSCursor.current == NSCursor.crosshair)

        NSCursor.arrow.set()
        overlay.mouseMoved(with: moved)
        #expect(NSCursor.current == NSCursor.crosshair)
    }

    @Test func appKitCursorUpdatesUseTheCurrentCaptureMode() throws {
        let overlay = try makeOverlay()
        let previous = NSCursor.current
        defer { previous.set() }
        let event = try #require(NSEvent.enterExitEvent(with: .cursorUpdate, location: .zero,
            modifierFlags: [], timestamp: 1, windowNumber: 0, context: nil,
            eventNumber: 1, trackingNumber: 0, userData: nil))

        for mode in CaptureMode.allCases {
            overlay.mode = mode
            NSCursor.arrow.set()
            overlay.cursorUpdate(with: event)
            #expect(NSCursor.current == (mode == .region || mode == .app ? NSCursor.pointingHand : NSCursor.crosshair))
        }
    }

    @Test func aModeChangeOnAHiddenCanvasDoesNotOverrideThePointer() throws {
        let overlay = try makeOverlay()
        let panel = CapturePanel(screen: overlay.snapshot.screen, view: overlay)
        let previous = NSCursor.current
        defer { panel.close(); previous.set() }

        NSCursor.arrow.set()
        overlay.mode = .region
        #expect(NSCursor.current == NSCursor.arrow)
    }
}
