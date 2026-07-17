import AVFoundation
import CoreImage

final class DepthOutputDelegate: NSObject, AVCaptureDepthDataOutputDelegate {
    struct Frame {
        let disparity: CIImage
        let range: ClosedRange<Float>
    }

    private var latest: Frame?
    private var smoothedRange: ClosedRange<Float>?
    private let lock = NSLock()

    func depthDataOutput(
        _ output: AVCaptureDepthDataOutput,
        didOutput depthData: AVDepthData,
        timestamp: CMTime,
        connection: AVCaptureConnection
    ) {
        // Converting unconditionally keeps one code path regardless of which formats the
        // device reports, and hands back a freshly allocated buffer the CIImage can retain.
        let disparityData = depthData.converting(toDepthDataType: kCVPixelFormatType_DisparityFloat32)
        let map = disparityData.depthDataMap
        guard let measured = Self.range(of: map) else { return }
        let range = smooth(measured)
        guard range.upperBound - range.lowerBound >= Constants.Portrait.minDisparitySpan else { return }
        let frame = Frame(disparity: CIImage(cvPixelBuffer: map), range: range)
        lock.withLock { latest = frame }
    }

    // Called only from the depth queue, which AVFoundation serialises.
    private func smooth(_ measured: ClosedRange<Float>) -> ClosedRange<Float> {
        guard let previous = smoothedRange else {
            smoothedRange = measured
            return measured
        }
        let rate = Constants.Portrait.disparityRangeSmoothing
        let lower = previous.lowerBound + (measured.lowerBound - previous.lowerBound) * rate
        let upper = previous.upperBound + (measured.upperBound - previous.upperBound) * rate
        let smoothed = lower...max(upper, lower + .ulpOfOne)
        smoothedRange = smoothed
        return smoothed
    }

    func takeLatestFrame() -> Frame? {
        lock.withLock { latest }
    }

    func clear() {
        lock.withLock { latest = nil }
        smoothedRange = nil
    }

    // Two scans of ~76k floats on the depth queue cost well under a millisecond. CIAreaMinMax
    // would be a GPU round-trip plus a readback stall on every frame, and could only give the
    // extremes — which are exactly the values that must not be trusted here.
    private static func range(of pixelBuffer: CVPixelBuffer) -> ClosedRange<Float>? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        func eachValue(_ body: (Float) -> Void) {
            for y in 0..<height {
                let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float.self)
                for x in 0..<width {
                    let value = row[x]
                    // Depth maps carry holes where the two cameras disagree.
                    guard value.isFinite else { continue }
                    body(value)
                }
            }
        }

        var minimum = Float.greatestFiniteMagnitude
        var maximum = -Float.greatestFiniteMagnitude
        var count = 0
        eachValue { value in
            minimum = min(minimum, value)
            maximum = max(maximum, value)
            count += 1
        }
        guard count > 0, minimum < maximum else { return nil }

        let bins = Constants.Portrait.disparityHistogramBins
        let scale = Float(bins - 1) / (maximum - minimum)
        var histogram = [Int](repeating: 0, count: bins)
        eachValue { value in
            histogram[Int((value - minimum) * scale)] += 1
        }

        let low = Self.value(
            atPercentile: Constants.Portrait.disparityLowPercentile,
            histogram: histogram, count: count, minimum: minimum, scale: scale
        )
        let high = Self.value(
            atPercentile: Constants.Portrait.disparityHighPercentile,
            histogram: histogram, count: count, minimum: minimum, scale: scale
        )
        guard low < high else { return nil }
        return low...high
    }

    private static func value(
        atPercentile percentile: Float,
        histogram: [Int],
        count: Int,
        minimum: Float,
        scale: Float
    ) -> Float {
        let target = Int(Float(count) * percentile)
        var cumulative = 0
        for (bin, binCount) in histogram.enumerated() {
            cumulative += binCount
            if cumulative >= target {
                return minimum + Float(bin) / scale
            }
        }
        return minimum + Float(histogram.count - 1) / scale
    }
}
