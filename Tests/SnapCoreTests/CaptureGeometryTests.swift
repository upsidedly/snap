import Foundation
import CoreGraphics
import Testing
@testable import SnapCore

@Test func arrowKeysWrapBothWays() {
    #expect(CaptureMode.select.stepping(1) == .region)
    #expect(CaptureMode.region.stepping(1) == .fullScreen)
    #expect(CaptureMode.fullScreen.stepping(1) == .select)
    #expect(CaptureMode.select.stepping(-1) == .fullScreen)
    #expect(CaptureMode.fullScreen.stepping(-1) == .region)
    #expect(CaptureMode.region.stepping(-1) == .select)
}

@Test func retinaCropPreservesPixelsAndClipsEdges() {
    let crop = CaptureGeometry.pixelCrop(
        selection: CGRect(x: 10.25, y: 20.25, width: 100.5, height: 50.5),
        canvas: CGSize(width: 1000, height: 500), pixels: CGSize(width: 2000, height: 1000))
    #expect(crop == CGRect(x: 20, y: 40, width: 202, height: 102))
    #expect(CaptureGeometry.pixelCrop(selection: CGRect(x: -5, y: -10, width: 25, height: 30),
        canvas: CGSize(width: 100, height: 100), pixels: CGSize(width: 200, height: 200))
        == CGRect(x: 0, y: 0, width: 40, height: 40))
}

@Test func reverseDragAndSecondaryDisplayCoordinates() {
    #expect(CaptureGeometry.rectangle(from: CGPoint(x: 90, y: 80), to: CGPoint(x: 20, y: 30))
        == CGRect(x: 20, y: 30, width: 70, height: 50))
    let screen = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
    let window = CaptureGeometry.appKitWindow(CGRect(x: -1800, y: 250, width: 900, height: 600), desktopTop: 1080)
    #expect(window == CGRect(x: -1800, y: 230, width: 900, height: 600))
    #expect(CaptureGeometry.localTopLeft(window, screen: screen)
        == CGRect(x: 120, y: 50, width: 900, height: 600))
}

@Test func accidentalClicksAndInvalidGeometryDoNotCapture() {
    let size = CGSize(width: 100, height: 100)
    #expect(CaptureGeometry.pixelCrop(selection: .zero, canvas: size, pixels: size) == nil)
    #expect(CaptureGeometry.pixelCrop(selection: CGRect(x: 120, y: 0, width: 50, height: 50), canvas: size, pixels: size) == nil)
    #expect(CaptureGeometry.pixelCrop(selection: CGRect(x: 0, y: 0, width: 50, height: 50), canvas: .zero, pixels: size) == nil)
}
