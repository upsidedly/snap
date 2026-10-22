import AppKit
import ScreenCaptureKit
import ImageIO
import UniformTypeIdentifiers
import SnapCore

struct DisplaySnapshot {
    let screen: NSScreen
    let image: CGImage

    @MainActor
    func cropped(to rect: CGRect) throws -> CGImage {
        guard let pixels = CaptureGeometry.pixelCrop(selection: rect, canvas: screen.frame.size,
            pixels: CGSize(width: image.width, height: image.height)),
              let cropped = image.cropping(to: pixels) else { throw SnapError.encodeFailed }
        return cropped
    }
}

struct WindowRegion: Equatable, Sendable {
    // Subregions share their containing window's ID; frame distinguishes each target.
    let id: CGWindowID
    let frame: CGRect
    let title: String
}

enum SnapError: LocalizedError {
    case noDisplay, encodeFailed, clipboardFailed
    var errorDescription: String? {
        switch self {
        case .noDisplay: "Snap couldn’t capture this display. Try again."
        case .encodeFailed: "Snap couldn’t create the PNG image. Try another screenshot."
        case .clipboardFailed: "macOS couldn’t copy the screenshot to the clipboard."
        }
    }
}

@MainActor
final class CaptureEngine {
    func snapshots() async throws -> [DisplaySnapshot] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ownWindows = content.windows.filter {
            $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier
        }
        var results: [DisplaySnapshot] = []
        for screen in NSScreen.screens {
            try Task.checkCancellation()
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let display = content.displays.first(where: { $0.displayID == number.uint32Value }) else { continue }
            let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
            let config = configuration(size: screen.frame.size, scale: screen.backingScaleFactor)
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            try Task.checkCancellation()
            results.append(DisplaySnapshot(screen: screen, image: image))
        }
        guard !results.isEmpty else { throw SnapError.noDisplay }
        return results
    }

    private func configuration(size: CGSize, scale: CGFloat) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.width = Int((size.width * scale).rounded())
        config.height = Int((size.height * scale).rounded())
        config.showsCursor = false
        config.capturesAudio = false
        config.captureResolution = .best
        return config
    }

    func windowRegions() -> [WindowRegion] {
        let desktopTop = NSScreen.screens.first?.frame.maxY ?? 0
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return [] }
        return windows.compactMap { row in
            guard (row[kCGWindowLayer as String] as? Int) == 0,
                  (row[kCGWindowOwnerPID as String] as? Int32) != ProcessInfo.processInfo.processIdentifier,
                  let id = row[kCGWindowNumber as String] as? UInt32,
                  let bounds = row[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"], let w = bounds["Width"], let h = bounds["Height"],
                  w >= 60, h >= 40 else { return nil }
            let owner = row[kCGWindowOwnerName as String] as? String ?? "Window"
            let name = row[kCGWindowName as String] as? String ?? ""
            return WindowRegion(id: id, frame: CaptureGeometry.appKitWindow(
                CGRect(x: x, y: y, width: w, height: h), desktopTop: desktopTop),
                title: name.isEmpty ? owner : "\(owner) — \(name)")
        }
    }
}

actor ScreenshotStore {
    func saveExactly(_ data: Data, url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    func encode(_ image: CGImage) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)
        else { throw SnapError.encodeFailed }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw SnapError.encodeFailed }
        return output as Data
    }

    func save(_ data: Data, directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss.SSS"
        let name = "Snap \(formatter.string(from: Date()))"
        var url = directory.appendingPathComponent(name).appendingPathExtension("png")
        var suffix = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(name) (\(suffix))").appendingPathExtension("png")
            suffix += 1
        }
        try data.write(to: url, options: .atomic)
        return url
    }
}
