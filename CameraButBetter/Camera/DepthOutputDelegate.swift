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
        guard let measured = DisparityStatistics.percentileRange(of: map) else { return }
        let range = smooth(measured)
        guard range.upperBound - range.lowerBound >= Constants.Portrait.minDisparitySpan else { return }
        // NSNull opts out of color management: disparity is data, not color, and Core Image
        // would otherwise sRGB-decode the floats — 0.8 would arrive at the mask math as 0.6
        // while the range was measured on the raw values, blurring the subject.
        let disparityImage = CIImage(cvPixelBuffer: map, options: [.colorSpace: NSNull()])
        let frame = Frame(disparity: disparityImage, range: range)
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
}
