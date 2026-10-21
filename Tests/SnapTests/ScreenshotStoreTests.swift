import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Snap

@Test func pngOutputIsLosslessAndCapturesDoNotOverwrite() async throws {
    let rgba: [UInt8] = [255, 0, 0, 255, 0, 255, 0, 255,
                         0, 0, 255, 255, 255, 255, 255, 255]
    let provider = try #require(CGDataProvider(data: Data(rgba) as CFData))
    let image = try #require(CGImage(width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let store = ScreenshotStore()
    let data = try await store.encode(image)
    #expect(Array(data.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10])
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(decoded.width == 2 && decoded.height == 2)
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Snap-tests-\(UUID())")
    defer { try? FileManager.default.removeItem(at: folder) }
    let first = try await store.save(data, directory: folder)
    let second = try await store.save(data, directory: folder)
    #expect(first != second)
    #expect(try Data(contentsOf: first) == data)
    #expect(try Data(contentsOf: second) == data)
}
