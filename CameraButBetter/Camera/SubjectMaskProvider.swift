import AVFoundation
import CoreImage
import Vision

final class SubjectMaskProvider {
    private let queue = DispatchQueue(label: "com.alaramartin.CameraButBetter.subjectMask", qos: .userInitiated)
    private let lock = NSLock()
    private var latest: CIImage?
    private var isProcessing = false

    // Queue-confined. The accumulator is rendered flat on every update: chaining each
    // frame's filters onto a lazy CIImage would grow the recipe without bound.
    private var accumulator: CIImage?
    private var accumulatorWeight: Float = 0
    private let renderContext = CIContext(options: [.useSoftwareRenderer: false])

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
            guard let self else { return }
            let mask = Self.mask(using: VNImageRequestHandler(cvPixelBuffer: pixelBuffer), disparity: disparity)
            let staged = self.integrate(mask)
            self.lock.withLock {
                self.latest = staged
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
        queue.async { [weak self] in
            self?.accumulator = nil
            self?.accumulatorWeight = 0
        }
    }

    static func mask(forCGImage cgImage: CGImage, disparity: CVPixelBuffer?) -> CIImage? {
        mask(using: VNImageRequestHandler(cgImage: cgImage), disparity: disparity)
    }

    // Vision's instance list flaps frame to frame, and rendering every flap instantly is what
    // made background objects flick between blurred and clear. New masks blend into an
    // exponential accumulator; a no-subject result decays it toward empty instead of clearing
    // it, so a single-frame flap becomes a faint transition.
    private func integrate(_ mask: CIImage?) -> CIImage? {
        let rate = Constants.Portrait.subjectMaskSmoothing
        if let mask {
            if let previous = accumulator, previous.extent == mask.extent {
                let blended = Self.scaled(mask, by: rate)
                    .applyingFilter("CIAdditionCompositing", parameters: [
                        kCIInputBackgroundImageKey: Self.scaled(previous, by: 1 - rate)
                    ])
                    .cropped(to: mask.extent)
                accumulator = rendered(blended) ?? mask
                accumulatorWeight = accumulatorWeight * (1 - rate) + rate
            } else {
                accumulator = mask
                accumulatorWeight = 1
            }
        } else {
            guard let previous = accumulator else { return nil }
            accumulatorWeight *= (1 - rate)
            if accumulatorWeight < 0.1 {
                accumulator = nil
                accumulatorWeight = 0
                return nil
            }
            accumulator = rendered(Self.scaled(previous, by: 1 - rate)) ?? previous
        }
        return accumulator
    }

    private func rendered(_ image: CIImage) -> CIImage? {
        guard let cgImage = renderContext.createCGImage(image, from: image.extent) else { return nil }
        return CIImage(cgImage: cgImage)
    }

    private static func scaled(_ image: CIImage, by factor: Float) -> CIImage {
        let factor = CGFloat(factor)
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: factor, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: factor, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: factor, w: 0)
        ])
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
            // The union of every lifted instance is never an acceptable answer: it is what
            // held background objects sharp. Unrankable instances mean depth-only instead.
            guard let instances = nearestInstance(in: observation, disparity: disparity) else { return nil }
            let buffer = try observation.generateScaledMaskForImage(forInstances: instances, from: handler)
            // A "subject" covering most of the frame is a segmentation failure, and zeroing
            // the blur under it would silently erase the effect.
            guard coverage(of: buffer) <= Constants.Portrait.subjectMaskMaxCoverage else { return nil }
            // NSNull opts out of color management — the mask is data, and sRGB-decoding its
            // floats would bend every value between the 0 and 1 endpoints.
            return CIImage(cvPixelBuffer: buffer, options: [.colorSpace: NSNull()])
        } catch {
            // A frame with no liftable subject is a normal outcome, not something the user
            // can act on; nil falls back to the depth-only mask downstream.
            return nil
        }
    }

    // Vision lifts every salient object, so a monitor a foot behind a laptop lands in the
    // union too and would be held sharp. The subject of a portrait is the nearest lifted
    // object, so instances are ranked by mean disparity over the pixels they cover; nil
    // means the ranking couldn't be performed.
    private static func nearestInstance(in observation: VNInstanceMaskObservation, disparity: CVPixelBuffer?) -> IndexSet? {
        let all = observation.allInstances
        guard all.count > 1 else { return all }
        guard let disparity, let top = all.max() else { return nil }

        let instanceMask = observation.instanceMask
        CVPixelBufferLockBaseAddress(instanceMask, .readOnly)
        CVPixelBufferLockBaseAddress(disparity, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(instanceMask, .readOnly)
            CVPixelBufferUnlockBaseAddress(disparity, .readOnly)
        }
        guard let maskBase = CVPixelBufferGetBaseAddress(instanceMask),
              let disparityBase = CVPixelBufferGetBaseAddress(disparity)
        else { return nil }

        let maskWidth = CVPixelBufferGetWidth(instanceMask)
        let maskHeight = CVPixelBufferGetHeight(instanceMask)
        let maskRowBytes = CVPixelBufferGetBytesPerRow(instanceMask)
        let disparityWidth = CVPixelBufferGetWidth(disparity)
        let disparityHeight = CVPixelBufferGetHeight(disparity)
        let disparityRowBytes = CVPixelBufferGetBytesPerRow(disparity)
        guard maskWidth > 0, maskHeight > 0, disparityWidth > 0, disparityHeight > 0 else { return nil }

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
        guard bestIndex >= 0 else { return nil }
        return IndexSet(integer: bestIndex)
    }

    // Stride-sampled mean of the full-resolution float mask — plenty to catch a mask that
    // covers most of the frame. Unreadable buffers count as full coverage, i.e. rejected.
    private static func coverage(of pixelBuffer: CVPixelBuffer) -> Float {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return 1 }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard width > 0, height > 0 else { return 1 }

        var sum = 0.0
        var count = 0
        var y = 0
        while y < height {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float.self)
            var x = 0
            while x < width {
                sum += Double(row[x])
                count += 1
                x += 4
            }
            y += 4
        }
        guard count > 0 else { return 1 }
        return Float(sum / Double(count))
    }
}
