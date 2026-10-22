import CoreGraphics

/// Finds shared pane dividers that don't form isolated, high-contrast rectangles.
struct PaneDetector {
    private let pixels: [UInt8]
    private let width: Int
    private let height: Int
    private let screen: CGRect

    init?(image: CGImage, screen: CGRect) {
        guard screen.width > 0, screen.height > 0 else { return nil }
        let scale = min(1, 1600 / Double(max(image.width, image.height)))
        let width = max(1, Int(Double(image.width) * scale))
        let height = max(1, Int(Double(image.height) * scale))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { storage in
            guard let context = CGContext(data: storage.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
            else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.pixels = pixels
        self.width = width
        self.height = height
        self.screen = screen
    }

    func regions(in window: CGRect) throws -> [CGRect] {
        let visible = window.intersection(screen)
        guard !visible.isNull else { return [] }
        // Bitmap rows start at the top; the stored window frames use AppKit's bottom-left origin.
        let bounds = CGRect(x: (visible.minX - screen.minX) * CGFloat(width) / screen.width,
                            y: (screen.maxY - visible.maxY) * CGFloat(height) / screen.height,
                            width: visible.width * CGFloat(width) / screen.width,
                            height: visible.height * CGFloat(height) / screen.height).integral
        var result: [CGRect] = []
        try divide(bounds.intersection(CGRect(x: 0, y: 0, width: width, height: height)), depth: 0, into: &result)
        return result.map { rect in
            CGRect(x: screen.minX + rect.minX * screen.width / CGFloat(width),
                   y: screen.maxY - rect.maxY * screen.height / CGFloat(height),
                   width: rect.width * screen.width / CGFloat(width),
                   height: rect.height * screen.height / CGFloat(height))
        }
    }

    private func divide(_ rect: CGRect, depth: Int, into result: inout [CGRect]) throws {
        try Task.checkCancellation()
        guard depth < 5 else { return }
        let vertical = separator(in: rect, vertical: true)
        let horizontal = separator(in: rect, vertical: false)
        let children: [CGRect]
        if let vertical, vertical.score >= (horizontal?.score ?? 0) {
            let x = CGFloat(vertical.position)
            children = [CGRect(x: rect.minX, y: rect.minY, width: x - rect.minX, height: rect.height),
                        CGRect(x: x, y: rect.minY, width: rect.maxX - x, height: rect.height)]
        } else if let horizontal {
            let y = CGFloat(horizontal.position)
            children = [CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: y - rect.minY),
                        CGRect(x: rect.minX, y: y, width: rect.width, height: rect.maxY - y)]
        } else { return }
        for child in children {
            result.append(child)
            try divide(child, depth: depth + 1, into: &result)
        }
    }

    private func separator(in rect: CGRect, vertical: Bool) -> (position: Int, score: Double)? {
        let start = Int(vertical ? rect.minX : rect.minY)
        let end = Int(vertical ? rect.maxX : rect.maxY)
        let crossStart = Int(vertical ? rect.minY : rect.minX)
        let crossEnd = Int(vertical ? rect.maxY : rect.maxX)
        let minimum = vertical ? Int(ceil(48 * CGFloat(width) / screen.width))
            : Int(ceil(32 * CGFloat(height) / screen.height))
        guard end - start >= minimum * 2, crossEnd > crossStart else { return nil }
        let step = max(1, (crossEnd - crossStart) / 400)
        var best: (position: Int, score: Double)?

        for position in (start + minimum)...(end - minimum) {
            var count = 0, hits = 0, contrast = 0
            var redA = 0, greenA = 0, blueA = 0, squaresA = 0
            var redB = 0, greenB = 0, blueB = 0, squaresB = 0
            for cross in stride(from: crossStart, to: crossEnd, by: step) {
                let a = ((vertical ? cross : position) * width + (vertical ? position : cross)) * 4
                let b = a - (vertical ? 4 : width * 4)
                let ar = Int(pixels[a]), ag = Int(pixels[a + 1]), ab = Int(pixels[a + 2])
                let br = Int(pixels[b]), bg = Int(pixels[b + 1]), bb = Int(pixels[b + 2])
                let difference = max(abs(ar - br), abs(ag - bg), abs(ab - bb))
                if difference >= 6 { hits += 1; contrast += difference }
                redA += ar; greenA += ag; blueA += ab
                redB += br; greenB += bg; blueB += bb
                squaresA += ar * ar + ag * ag + ab * ab
                squaresB += br * br + bg * bg + bb * bb
                count += 1
            }
            guard hits * 4 >= count * 3 else { continue }
            // A divider has a nearly uniform colour on at least one side. Texture and text don't.
            let n = Double(count)
            let varianceA = Double(squaresA) / n - Double(redA * redA + greenA * greenA + blueA * blueA) / (n * n)
            let varianceB = Double(squaresB) / n - Double(redB * redB + greenB * greenB + blueB * blueB) / (n * n)
            guard min(varianceA, varianceB) < 3 * 12 * 12 else { continue }
            let score = Double(hits) / n + Double(contrast) / n / 255 * 0.05
            if score > (best?.score ?? 0) { best = (position, score) }
        }
        return best
    }
}
