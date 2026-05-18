import AVFoundation

final class FrameOutputDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private var latestBuffer: CMSampleBuffer?
    private let lock = NSLock()

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        lock.withLock { latestBuffer = sampleBuffer }
    }

    func takeLatestBuffer() -> CMSampleBuffer? {
        lock.withLock { latestBuffer }
    }
}
