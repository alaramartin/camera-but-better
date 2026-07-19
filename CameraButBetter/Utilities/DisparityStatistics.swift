import CoreVideo

enum DisparityStatistics {
    // Two scans of ~76k floats cost well under a millisecond. CIAreaMinMax would be a GPU
    // round-trip plus a readback stall, and could only give the extremes — which are exactly
    // the values that must not be trusted here: depth maps carry outlier pixels reading far
    // nearer than anything real, so the range is taken between percentiles instead.
    static func percentileRange(of pixelBuffer: CVPixelBuffer) -> ClosedRange<Float>? {
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

        let low = value(
            atPercentile: Constants.Portrait.disparityLowPercentile,
            histogram: histogram, count: count, minimum: minimum, scale: scale
        )
        let high = value(
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
