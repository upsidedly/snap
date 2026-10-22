import AppKit
import SnapCore
import Testing
@testable import Snap

@Suite @MainActor
struct RegionCaptureTests {
    private func canvas() throws -> (SelectionOverlay, WindowRegion, WindowRegion, WindowRegion) {
        _ = NSApplication.shared
        let screen = try #require(NSScreen.main)
        let context = try #require(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let window = WindowRegion(id: 10, frame: screen.frame.insetBy(dx: 30, dy: 30), title: "App")
        let pane = WindowRegion(id: 10, frame: window.frame.insetBy(dx: 40, dy: 40), title: "App")
        let section = WindowRegion(id: 10, frame: pane.frame.insetBy(dx: 50, dy: 50), title: "App")
        let overlay = SelectionOverlay(snapshot: DisplaySnapshot(screen: screen,
            image: try #require(context.makeImage())), windows: [window])
        overlay.setDetectedRegions([pane, section])
        return (overlay, window, pane, section)
    }

    @Test func regionChoosesTheSmallestSectionAndAppChoosesTheWholeWindow() throws {
        let (overlay, window, _, section) = try canvas()
        let point = CGPoint(x: section.frame.midX, y: section.frame.midY)
        var captured: WindowRegion?
        overlay.onCapture = { if case let .window(_, region) = $0 { captured = region } }

        overlay.mode = .region
        overlay.updateHover(at: point)
        overlay.capture()
        #expect(captured == section)

        overlay.mode = .app
        overlay.updateHover(at: point)
        overlay.capture()
        #expect(captured == window)
    }

    @Test func regionsInCoveredWindowsNeverWinTheHitTest() throws {
        let (canvas, front, _, section) = try canvas()
        let back = WindowRegion(id: 20, frame: front.frame, title: "Covered app")
        let coveredSection = WindowRegion(id: 20,
            frame: section.frame.insetBy(dx: 20, dy: 20), title: "Covered app")
        let overlay = SelectionOverlay(snapshot: canvas.snapshot, windows: [front, back])
        overlay.setDetectedRegions([coveredSection, section])
        overlay.mode = .region
        overlay.updateHover(at: CGPoint(x: section.frame.midX, y: section.frame.midY))
        #expect(overlay.hoveredRegion == section)
    }

    @Test func missingSectionsFallBackToTheWindowAndEmptySpaceClearsTheTarget() throws {
        let (overlay, window, _, section) = try canvas()
        overlay.mode = .region
        overlay.setDetectedRegions([])
        overlay.updateHover(at: CGPoint(x: section.frame.midX, y: section.frame.midY))
        #expect(overlay.hoveredRegion == window)
        overlay.updateHover(at: CGPoint(x: window.frame.minX - 10, y: window.frame.minY))
        #expect(overlay.hoveredRegion == nil)
    }

    @Test func keyboardCanReachNestedSectionsAndAppOnlyCyclesWindows() throws {
        let (overlay, window, pane, section) = try canvas()
        overlay.mode = .region
        overlay.updateHover(at: CGPoint(x: section.frame.midX, y: section.frame.midY))
        overlay.cycleRegion(-1)
        #expect(overlay.hoveredRegion == pane)
        overlay.cycleRegion(-1)
        #expect(overlay.hoveredRegion == window)
        overlay.cycleRegion(-1)
        #expect(overlay.hoveredRegion == section)
        // A background detector finishing must not undo a keyboard choice.
        overlay.setDetectedRegions([pane, section])
        #expect(overlay.hoveredRegion == section)

        overlay.mode = .app
        overlay.cycleRegion(1)
        #expect(overlay.hoveredRegion == window)
    }

    @Test func nativeClicksCaptureASectionOrItsAppFromANonactivatingPanel() throws {
        let (overlay, window, _, section) = try canvas()
        let panel = CapturePanel(screen: overlay.snapshot.screen, view: overlay)
        defer { panel.close() }
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        var captured: WindowRegion?
        overlay.onCapture = { if case let .window(_, region) = $0 { captured = region } }
        let point = CGPoint(x: section.frame.midX - overlay.snapshot.screen.frame.minX,
                            y: section.frame.midY - overlay.snapshot.screen.frame.minY)
        for mode in [CaptureMode.region, .app] {
            overlay.mode = mode
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                    timestamp: 1, windowNumber: panel.windowNumber, context: nil,
                    eventNumber: 1, clickCount: 1, pressure: 1))
                if type == .leftMouseDown { overlay.mouseDown(with: event) }
                else { overlay.mouseUp(with: event) }
            }
            #expect(captured == (mode == .region ? section : window))
        }
    }

    @Test func toolbarFitsAllFourModesAndALongSaveFolderName() throws {
        let toolbar = CaptureToolbar()
        defer { toolbar.close() }
        toolbar.update(mode: .app, savesToFile: true,
            directory: URL(fileURLWithPath: "/tmp/A long screenshot folder name"))
        let content = try #require(toolbar.contentView)
        content.layoutSubtreeIfNeeded()
        let row = try #require(content.subviews.first as? NSStackView)
        let segments = try #require(row.arrangedSubviews.first as? NSSegmentedControl)
        #expect(segments.segmentCount == 4)
        #expect(segments.selectedSegment == CaptureMode.app.rawValue)
        #expect((0..<segments.segmentCount).compactMap { segments.label(forSegment: $0) }
            == ["Select", "Region", "App", "Full Screen"])
        #expect(row.frame.minX >= 9)
        #expect(row.frame.maxX <= content.bounds.maxX - 9)
        #expect(segments.frame.width >= segments.intrinsicContentSize.width)
        #expect(toolbar.styleMask.contains(.nonactivatingPanel))
    }
}

struct RegionDetectorTests {
    private func fixture() throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: 1000, height: 700, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0.12, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1000, height: 700))
        for rect in [CGRect(x: 60, y: 70, width: 260, height: 560),
                     CGRect(x: 360, y: 70, width: 580, height: 250),
                     CGRect(x: 360, y: 360, width: 580, height: 270)] {
            context.setFillColor(CGColor(gray: 0.85, alpha: 1))
            context.fill(rect)
        }
        return try #require(context.makeImage())
    }

    @Test func findsMultipleSectionsAndMapsRetinaAndNegativeDisplayCoordinates() async throws {
        let screen = CGRect(x: -500, y: -100, width: 500, height: 350)
        let window = WindowRegion(id: 7, frame: screen, title: "Split app")
        let regions = try await RegionDetector().regions(in: fixture(), screen: screen, windows: [window])
        #expect(regions.count >= 3)
        for expected in [CGRect(x: -470, y: -65, width: 130, height: 280),
                         CGRect(x: -320, y: -65, width: 290, height: 125),
                         CGRect(x: -320, y: 80, width: 290, height: 135)] {
            #expect(regions.contains { region in
                region.id == window.id && abs(region.frame.minX - expected.minX) < 4
                    && abs(region.frame.minY - expected.minY) < 4
                    && abs(region.frame.width - expected.width) < 8
                    && abs(region.frame.height - expected.height) < 8
            })
        }
    }

    @Test func cancellationDiscardsDetectionResults() async throws {
        let image = try fixture()
        let task = Task {
            try await RegionDetector().regions(in: image,
                screen: CGRect(x: 0, y: 0, width: 1000, height: 700), windows: [])
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
