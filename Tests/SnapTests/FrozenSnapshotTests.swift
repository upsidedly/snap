import AppKit
import Testing
@testable import Snap

@MainActor
@Test func croppingPreservesTheOriginalFrameAfterContentChanges() throws {
    _ = NSApplication.shared
    let screen = try #require(NSScreen.main)
    let context = try #require(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let bounds = CGRect(x: 0, y: 0, width: 8, height: 8)
    context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
    context.fill(bounds)
    let snapshot = DisplaySnapshot(screen: screen, image: try #require(context.makeImage()))

    // Simulate the underlying screen changing while the user chooses a region.
    context.setFillColor(red: 0, green: 1, blue: 0, alpha: 1)
    context.fill(bounds)
    let selection = CGRect(x: 0, y: 0,
        width: screen.frame.width / 2, height: screen.frame.height)
    let cropped = try snapshot.cropped(to: selection)
    #expect(cropped.width == 4 && cropped.height == 8)
    let preserved = try #require(cropped.dataProvider?.data) as Data
    #expect(Array(preserved.prefix(4)) == [255, 0, 0, 255])

    let changedImage = try #require(context.makeImage())
    let changed = try #require(changedImage.dataProvider?.data) as Data
    #expect(Array(changed.prefix(4)) == [0, 255, 0, 255])
}
