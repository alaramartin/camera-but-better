import AVFoundation

final class FrameOutputDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private var latestBuffer: CMSampleBuffer?
    private var frameHandler: ((CMSampleBuffer) -> Void)?
    private let lock = NSLock()

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let handler = lock.withLock { () -> ((CMSampleBuffer) -> Void)? in
            latestBuffer = sampleBuffer
            return frameHandler
        }
        handler?(sampleBuffer)
    }

    func takeLatestBuffer() -> CMSampleBuffer? {
        lock.withLock { latestBuffer }
    }

    func setFrameHandler(_ handler: ((CMSampleBuffer) -> Void)?) {
        lock.withLock { frameHandler = handler }
    }
}
