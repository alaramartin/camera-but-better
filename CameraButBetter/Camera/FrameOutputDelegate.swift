import AVFoundation

final class FrameOutputDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private var latestBuffer: CMSampleBuffer?
    private var frameHandlers: [String: (CMSampleBuffer) -> Void] = [:]
    private let lock = NSLock()

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let handlers = lock.withLock { () -> [(CMSampleBuffer) -> Void] in
            latestBuffer = sampleBuffer
            return Array(frameHandlers.values)
        }
        for handler in handlers {
            handler(sampleBuffer)
        }
    }

    func takeLatestBuffer() -> CMSampleBuffer? {
        lock.withLock { latestBuffer }
    }

    func setFrameHandler(_ handler: @escaping (CMSampleBuffer) -> Void, forKey key: String) {
        lock.withLock { frameHandlers[key] = handler }
    }

    func removeFrameHandler(forKey key: String) {
        lock.withLock { frameHandlers[key] = nil }
    }
}
