import SwiftUI
import MetalKit
import CoreImage
import AVFoundation

struct BloomPreviewView: UIViewRepresentable {
    let frameDelegate: FrameOutputDelegate
    let intensity: Double

    func makeCoordinator() -> BloomRenderer {
        BloomRenderer(frameDelegate: frameDelegate)
    }

    func makeUIView(context: Context) -> BloomMetalView {
        let view = BloomMetalView()
        view.renderer = context.coordinator
        context.coordinator.attach(to: view)
        context.coordinator.intensity = Float(intensity)
        return view
    }

    func updateUIView(_ uiView: BloomMetalView, context: Context) {
        context.coordinator.intensity = Float(intensity)
    }

    static func dismantleUIView(_ uiView: BloomMetalView, coordinator: BloomRenderer) {
        coordinator.detach()
    }
}

final class BloomMetalView: MTKView {
    weak var renderer: BloomRenderer?

    override func layoutSubviews() {
        super.layoutSubviews()
        renderer?.updateOrientation(interfaceOrientation)
    }

    private var interfaceOrientation: UIInterfaceOrientation {
        window?.windowScene?.interfaceOrientation ?? .portrait
    }
}

final class BloomRenderer: NSObject, MTKViewDelegate {
    private let frameDelegate: FrameOutputDelegate

    private let device: MTLDevice?
    private let ciContext: CIContext?
    private let commandQueue: MTLCommandQueue?
    private let colorSpace = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()

    private let lock = NSLock()
    private var latestImage: CIImage?
    private var orientation: CGImagePropertyOrientation = .right

    // Set and read on the main thread (updateUIView and draw(in:)).
    var intensity: Float = 0

    init(frameDelegate: FrameOutputDelegate) {
        self.frameDelegate = frameDelegate
        if let device = MTLCreateSystemDefaultDevice() {
            self.device = device
            ciContext = CIContext(mtlDevice: device, options: [.useSoftwareRenderer: false])
            commandQueue = device.makeCommandQueue()
        } else {
            device = nil
            ciContext = nil
            commandQueue = nil
        }
        super.init()
    }

    func attach(to view: BloomMetalView) {
        view.device = device
        view.delegate = self
        view.framebufferOnly = false
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.isOpaque = true
        view.backgroundColor = .black
        // The frame callback runs on the video queue: it only stages the latest image.
        // All drawable access happens in draw(in:) on the main thread to avoid the
        // "addPresentedHandler cannot be called after drawable has been presented" race.
        frameDelegate.setFrameHandler({ [weak self, weak view] sampleBuffer in
            self?.ingest(sampleBuffer)
            DispatchQueue.main.async { view?.setNeedsDisplay() }
        }, forKey: "preview")
    }

    func detach() {
        frameDelegate.removeFrameHandler(forKey: "preview")
        lock.withLock { latestImage = nil }
    }

    func updateOrientation(_ interfaceOrientation: UIInterfaceOrientation) {
        lock.withLock { orientation = Self.imageOrientation(for: interfaceOrientation) }
    }

    private func ingest(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let orientation = lock.withLock { self.orientation }
        let image = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
        lock.withLock { latestImage = image }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let ciContext, let commandQueue,
              let drawable = view.currentDrawable
        else { return }
        let size = view.drawableSize
        guard size.width > 0, size.height > 0 else { return }
        guard let image = lock.withLock({ latestImage }) else { return }

        let bloomed = BloomEffect.apply(to: image, intensity: intensity)
        let filled = Self.aspectFill(bloomed, to: size)

        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        ciContext.render(
            filled,
            to: drawable.texture,
            commandBuffer: commandBuffer,
            bounds: CGRect(origin: .zero, size: size),
            colorSpace: colorSpace
        )
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private static func aspectFill(_ image: CIImage, to size: CGSize) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }
        let scale = max(size.width / extent.width, size.height / extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let dx = (size.width - scaled.extent.width) / 2 - scaled.extent.origin.x
        let dy = (size.height - scaled.extent.height) / 2 - scaled.extent.origin.y
        return scaled
            .transformed(by: CGAffineTransform(translationX: dx, y: dy))
            .cropped(to: CGRect(origin: .zero, size: size))
    }

    private static func imageOrientation(for interfaceOrientation: UIInterfaceOrientation) -> CGImagePropertyOrientation {
        switch interfaceOrientation {
        case .portrait: return .right
        case .portraitUpsideDown: return .left
        case .landscapeLeft: return .down
        case .landscapeRight: return .up
        default: return .right
        }
    }
}
