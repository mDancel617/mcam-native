//
//  CameraPreviewView.swift
//  LeicaStyleCam
//
//  Renders the look-processed CIImage live using Metal (MTKView) so the
//  viewfinder shows exactly what the saved file will look like (WYSIWYG).
//

import SwiftUI
import MetalKit
import CoreImage

struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var camera: CameraViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(context: camera.sharedContext)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.framebufferOnly = false
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 30
        view.delegate = context.coordinator
        view.contentMode = .scaleAspectFill
        context.coordinator.mtkView = view
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.image = camera.previewImage
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        let ciContext: CIContext
        let commandQueue: MTLCommandQueue?
        weak var mtkView: MTKView?
        var image: CIImage?

        init(context: CIContext) {
            self.ciContext = context
            self.commandQueue = MTLCreateSystemDefaultDevice()?.makeCommandQueue()
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let image,
                  let drawable = view.currentDrawable,
                  let commandBuffer = commandQueue?.makeCommandBuffer() else { return }

            let dstSize = view.drawableSize

            // Aspect-fill the sensor image into the view.
            let imgExtent = image.extent
            guard imgExtent.width > 0, imgExtent.height > 0 else { return }
            let scale = max(dstSize.width / imgExtent.width,
                            dstSize.height / imgExtent.height)
            let scaled = image
                .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let scaledExtent = scaled.extent
            let tx = (dstSize.width - scaledExtent.width) / 2 - scaledExtent.origin.x
            let ty = (dstSize.height - scaledExtent.height) / 2 - scaledExtent.origin.y
            let centered = scaled.transformed(by: CGAffineTransform(translationX: tx, y: ty))

            let bounds = CGRect(origin: .zero, size: dstSize)
            let colorSpace = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()

            ciContext.render(centered,
                             to: drawable.texture,
                             commandBuffer: commandBuffer,
                             bounds: bounds,
                             colorSpace: colorSpace)

            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}
