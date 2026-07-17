import AVFoundation
import CoreImage

final class VideoRecorder: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    let recordingQueue = DispatchQueue(label: "com.alaramartin.CameraButBetter.recording", qos: .userInitiated)
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let colorSpace = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()

    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?

    private var outputURL: URL?
    private var orientation: CGImagePropertyOrientation = .right
    private var aspectRatio: PreviewAspectRatio = .fourThree
    private var bloomIntensity: Float = 0

    private var started = false
    private var finished = false

    func start(url: URL, orientation: CGImagePropertyOrientation, aspectRatio: PreviewAspectRatio, bloomIntensity: Float) {
        recordingQueue.async {
            self.outputURL = url
            self.orientation = orientation
            self.aspectRatio = aspectRatio
            self.bloomIntensity = bloomIntensity
            self.started = false
            self.finished = false
        }
    }

    // Called from the video-output queue; hands off to the serial recording queue so all
    // writer appends (video and audio) are serialized on a single queue.
    func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        recordingQueue.async {
            guard !self.finished, let url = self.outputURL,
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
            else { return }
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

            let oriented = CIImage(cvPixelBuffer: pixelBuffer).oriented(self.orientation)
            let cropped = Self.crop(oriented, to: self.aspectRatio)
            let processed = BloomEffect.apply(to: cropped, intensity: self.bloomIntensity)
            let outputImage = processed.transformed(
                by: CGAffineTransform(translationX: -processed.extent.origin.x, y: -processed.extent.origin.y)
            )

            if !self.started {
                let size = CGSize(
                    width: (processed.extent.width / 2).rounded() * 2,
                    height: (processed.extent.height / 2).rounded() * 2
                )
                guard self.beginWriting(url: url, size: size, atSourceTime: presentationTime) else { return }
                self.started = true
            }

            guard let videoInput = self.videoInput, videoInput.isReadyForMoreMediaData,
                  let adaptor = self.adaptor, let pool = adaptor.pixelBufferPool
            else { return }

            var outBuffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outBuffer) == kCVReturnSuccess,
                  let outBuffer else { return }

            self.ciContext.render(
                outputImage,
                to: outBuffer,
                bounds: CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(outBuffer), height: CVPixelBufferGetHeight(outBuffer)),
                colorSpace: self.colorSpace
            )
            adaptor.append(outBuffer, withPresentationTime: presentationTime)
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Audio-only output; video frames come through appendVideo.
        recordingQueue.async {
            guard self.started, !self.finished,
                  let audioInput = self.audioInput, audioInput.isReadyForMoreMediaData
            else { return }
            audioInput.append(sampleBuffer)
        }
    }

    func finish(completion: @escaping (Result<URL, Error>) -> Void) {
        recordingQueue.async {
            guard !self.finished else { return }
            self.finished = true
            guard self.started, let writer = self.writer, let url = self.outputURL else {
                completion(.failure(RecorderError.noFrames))
                return
            }
            self.videoInput?.markAsFinished()
            self.audioInput?.markAsFinished()
            writer.finishWriting {
                if writer.status == .completed {
                    completion(.success(url))
                } else {
                    completion(.failure(writer.error ?? RecorderError.writeFailed))
                }
                self.writer = nil
                self.videoInput = nil
                self.audioInput = nil
                self.adaptor = nil
            }
        }
    }

    private func beginWriting(url: URL, size: CGSize, atSourceTime time: CMTime) -> Bool {
        do {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

            let videoSettings: [String: Any] = [
                AVVideoCodecKey: Constants.Recording.videoCodec,
                AVVideoWidthKey: size.width,
                AVVideoHeightKey: size.height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: Constants.Recording.videoBitRate
                ]
            ]
            let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput.expectsMediaDataInRealTime = true
            guard writer.canAdd(videoInput) else { return false }
            writer.add(videoInput)

            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: videoInput,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: size.width,
                    kCVPixelBufferHeightKey as String: size.height
                ]
            )

            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: Constants.Recording.audioSettings)
            audioInput.expectsMediaDataInRealTime = true
            if writer.canAdd(audioInput) {
                writer.add(audioInput)
                self.audioInput = audioInput
            }

            guard writer.startWriting() else { return false }
            writer.startSession(atSourceTime: time)

            self.writer = writer
            self.videoInput = videoInput
            self.adaptor = adaptor
            return true
        } catch {
            return false
        }
    }

    private static func crop(_ image: CIImage, to ratio: PreviewAspectRatio) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }
        let targetRatio = ratio.portraitRatio
        var cropWidth = extent.width
        var cropHeight = extent.width / targetRatio
        if cropHeight > extent.height {
            cropHeight = extent.height
            cropWidth = extent.height * targetRatio
        }
        let cropRect = CGRect(
            x: extent.origin.x + ((extent.width - cropWidth) / 2).rounded(),
            y: extent.origin.y + ((extent.height - cropHeight) / 2).rounded(),
            width: cropWidth.rounded(),
            height: cropHeight.rounded()
        )
        return image.cropped(to: cropRect)
    }

    enum RecorderError: LocalizedError {
        case noFrames
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .noFrames: return "Recording produced no video."
            case .writeFailed: return "Couldn't save the recording."
            }
        }
    }
}
