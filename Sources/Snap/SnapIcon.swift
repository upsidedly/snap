import AppKit

enum SnapIcon {
    /// The same capture frame is used in the menu bar and the app icon.
    static func drawMark(in rect: CGRect, color: NSColor) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let transform = NSAffineTransform()
        transform.translateX(by: rect.minX, yBy: rect.minY)
        transform.scaleX(by: rect.width / 24, yBy: rect.height / 24)
        transform.concat()
        color.setStroke()
        let corners = NSBezierPath()
        corners.lineWidth = 1.975
        corners.lineCapStyle = .round
        corners.lineJoinStyle = .round
        for (x, y, dx, dy) in [(3.0, 3.0, 1.0, 1.0), (21.0, 3.0, -1.0, 1.0),
                               (3.0, 21.0, 1.0, -1.0), (21.0, 21.0, -1.0, -1.0)] {
            corners.move(to: CGPoint(x: x + dx * 4.25, y: y))
            corners.line(to: CGPoint(x: x, y: y))
            corners.line(to: CGPoint(x: x, y: y + dy * 4.25))
        }
        corners.stroke()
        color.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: CGRect(x: 8.2, y: 9, width: 7.6, height: 6),
            xRadius: 0.7, yRadius: 0.7).fill()
    }

    static func menuBarImage() -> NSImage {
        let image = NSImage(size: CGSize(width: 18, height: 18), flipped: false) { bounds in
            drawMark(in: bounds, color: .black)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Snap"
        return image
    }
}
