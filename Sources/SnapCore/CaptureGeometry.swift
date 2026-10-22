import Foundation
import CoreGraphics

public enum CaptureMode: Int, CaseIterable, Sendable {
    case select, region, app, fullScreen

    public var title: String {
        switch self {
        case .select: "Select"
        case .region: "Region"
        case .app: "App"
        case .fullScreen: "Full Screen"
        }
    }

    public func stepping(_ direction: Int) -> Self {
        let count = Self.allCases.count
        return Self(rawValue: ((rawValue + direction) % count + count) % count) ?? .select
    }
}

public enum CaptureGeometry {
    /// Selection coordinates and image pixels both start at the top-left.
    /// Round outwards so a Retina selection never drops its outermost pixels.
    public static func pixelCrop(selection: CGRect, canvas: CGSize, pixels: CGSize) -> CGRect? {
        guard canvas.width > 0, canvas.height > 0, pixels.width > 0, pixels.height > 0,
              selection.origin.x.isFinite, selection.origin.y.isFinite,
              selection.width.isFinite, selection.height.isFinite else { return nil }
        let clipped = selection.standardized.intersection(CGRect(origin: .zero, size: canvas))
        guard !clipped.isNull, clipped.width >= 2, clipped.height >= 2 else { return nil }
        let sx = pixels.width / canvas.width, sy = pixels.height / canvas.height
        return CGRect(x: floor(clipped.minX * sx), y: floor(clipped.minY * sy),
                      width: ceil(clipped.maxX * sx) - floor(clipped.minX * sx),
                      height: ceil(clipped.maxY * sy) - floor(clipped.minY * sy))
            .intersection(CGRect(origin: .zero, size: pixels))
    }

    public static func rectangle(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    /// Quartz's desktop origin is the top-left of the primary display;
    /// AppKit's is the bottom-left, including displays with negative origins.
    public static func appKitWindow(_ quartz: CGRect, desktopTop: CGFloat) -> CGRect {
        CGRect(x: quartz.minX, y: desktopTop - quartz.maxY,
               width: quartz.width, height: quartz.height)
    }

    public static func localTopLeft(_ global: CGRect, screen: CGRect) -> CGRect {
        CGRect(x: global.minX - screen.minX, y: screen.maxY - global.maxY,
               width: global.width, height: global.height)
    }
}
