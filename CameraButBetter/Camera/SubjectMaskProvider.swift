import AVFoundation
import CoreImage
import Vision

final class SubjectMaskProvider {
    private let queue = DispatchQueue(label: "com.alaramartin.CameraButBetter.subjectMask", qos: .userInitiated)
    private let lock = NSLock()
    private var latest: CIImage?
    private var isProcessing = false

    // Segmentation takes tens of milliseconds, so frames arriving while a request is in
    // flight are dropped and the preview keeps rendering with the latest finished mask —
    // the same latest-wins pattern the depth delegate uses.
    func submit(_ sampleBuffer: CMSampleBuffer, disparity: CVPixelBuffer?) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let shouldRun: Bool = lock.withLock {
            if isProcessing { return false }
            isProcessing = true
            return true
        }
        guard shouldRun else { return }
        queue.async { [weak self] in
            let mask = Self.mask(using: VNImageRequestHandler(cvPixelBuffer: pixelBuffer), disparity: disparity)
            guard let self else { return }
            self.lock.withLock {
                self.latest = mask
                self.isProcessing = false
            }
        }
    }

    func takeLatestMask() -> CIImage? {
        lock.withLock { latest }
    }

    func clear() {
        lock.withLock {
            latest = nil
            isProcessing = false
        }
    }

    // No orientation is handed to Vision on purpose: every consumer of the mask works in
    // unrotated sensor space, and the instance-index scan below has to line up with the
    // unrotated disparity map. The lifting model tolerates rotated content.
    private static func mask(using handler: VNImageRequestHandler, disparity: CVPixelBuffer?) -> CIImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        do {
            try handler.perform([request])
            guard let observation = request.results?.first,
                  !observation.allInstances.isEmpty
            else { return nil }
            let buffer = try observation.generateScaledMaskForImage(
                forInstances: nearestInstance(in: observation, disparity: disparity),
                from: handler
            )
            return CIImage(cvPixelBuffer: buffer)
        } catch {
            // A frame with no liftable subject is a normal outcome, not something the user
            // can act on; nil falls back to the depth-only mask downstream.
            return nil
        }
    }

    // Vision lifts every salient object, so a monitor a foot behind a laptop lands in the
    // union too and would be held sharp. The subject of a portrait is the nearest lifted
    // object, so instances are ranked by mean disparity over the pixels they cover.
    private static func nearestInstance(in observation: VNInstanceMaskObservation, disparity: CVPixelBuffer?) -> IndexSet {
        let all = observation.allInstances
        guard all.count > 1, let disparity, let top = all.max() else { return all }

        let instanceMask = observation.instanceMask
        CVPixelBufferLockBaseAddress(instanceMask, .readOnly)
        CVPixelBufferLockBaseAddress(disparity, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(instanceMask, .readOnly)
            CVPixelBufferUnlockBaseAddress(disparity, .readOnly)
        }
        guard let maskBase = CVPixelBufferGetBaseAddress(instanceMask),
              let disparityBase = CVPixelBufferGetBaseAddress(disparity)
        else { return all }

        let maskWidth = CVPixelBufferGetWidth(instanceMask)
        let maskHeight = CVPixelBufferGetHeight(instanceMask)
        let maskRowBytes = CVPixelBufferGetBytesPerRow(instanceMask)
        let disparityWidth = CVPixelBufferGetWidth(disparity)
        let disparityHeight = CVPixelBufferGetHeight(disparity)
        let disparityRowBytes = CVPixelBufferGetBytesPerRow(disparity)
        guard maskWidth > 0, maskHeight > 0, disparityWidth > 0, disparityHeight > 0 else { return all }

        var sums = [Double](repeating: 0, count: top + 1)
        var counts = [Int](repeating: 0, count: top + 1)
        for y in 0..<maskHeight {
            let maskRow = maskBase.advanced(by: y * maskRowBytes).assumingMemoryBound(to: UInt8.self)
            let disparityRow = disparityBase
                .advanced(by: (y * disparityHeight / maskHeight) * disparityRowBytes)
                .assumingMemoryBound(to: Float.self)
            for x in 0..<maskWidth {
                let index = Int(maskRow[x])
                guard index != 0, index <= top else { continue }
                let value = disparityRow[x * disparityWidth / maskWidth]
                guard value.isFinite else { continue }
                sums[index] += Double(value)
                counts[index] += 1
            }
        }

        var bestIndex = -1
        var bestMean = -Double.infinity
        for index in all where index <= top && counts[index] > 0 {
            let mean = sums[index] / Double(counts[index])
            if mean > bestMean {
                bestMean = mean
                bestIndex = index
            }
        }
        guard bestIndex >= 0 else { return all }
        return IndexSet(integer: bestIndex)
    }
}
