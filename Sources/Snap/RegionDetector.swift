import CoreGraphics
import Vision

/// Finds rectangular sections in the frozen image, without inspecting other apps' accessibility trees.
actor RegionDetector {
    func regions(in image: CGImage, screen: CGRect, windows: [WindowRegion]) throws -> [WindowRegion] {
        try Task.checkCancellation()
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 64
        request.minimumAspectRatio = 0.05
        request.minimumSize = 0.025
        request.minimumConfidence = 0.5
        request.quadratureTolerance = 5
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        try Task.checkCancellation()

        var regions: [WindowRegion] = []
        for observation in request.results ?? [] {
            let box = observation.boundingBox
            // Vision and AppKit both use a bottom-left origin here.
            let frame = CGRect(x: screen.minX + box.minX * screen.width,
                               y: screen.minY + box.minY * screen.height,
                               width: box.width * screen.width, height: box.height * screen.height)
            guard frame.width >= 48, frame.height >= 32,
                  let window = windows.first(where: { $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) }),
                  window.frame.insetBy(dx: -2, dy: -2).contains(frame),
                  frame.width * frame.height < window.frame.width * window.frame.height * 0.95 else { continue }
            let clipped = frame.intersection(window.frame).intersection(screen)
            // Rectangle detectors can return both sides of a border. Keep one target per section.
            guard !regions.contains(where: { existing in
                existing.id == window.id && abs(existing.frame.minX - clipped.minX) < 4
                    && abs(existing.frame.minY - clipped.minY) < 4
                    && abs(existing.frame.width - clipped.width) < 8
                    && abs(existing.frame.height - clipped.height) < 8
            }) else { continue }
            regions.append(WindowRegion(id: window.id, frame: clipped, title: window.title))
        }
        return regions.sorted { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }
}
