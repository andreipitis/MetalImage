//
//  RenderView.swift
//  MetalImage
//
//  Created by Andrei-Sergiu Pițiș on 05/06/2017.
//  Copyright © 2017 Andrei-Sergiu Pițiș. All rights reserved.
//

#if os(iOS)
    import UIKit

    public class View: UIView {}
#elseif os(OSX)
    import AppKit

    public class View: NSView {}
#endif

import CoreMedia
import Metal

public enum FillMode {
    case stretch
    case aspectFit
    case aspectFill

    func convert(vertices: [Float], fromSize: CGSize, toSize: CGSize) -> [Float] {
        let aspectRatio = fromSize.width / fromSize.height
        let targetAspectRatio = toSize.width / toSize.height

        let xRatio: Float
        let yRatio: Float

        switch self {
        case .stretch:
            return vertices
        case .aspectFit:
            if aspectRatio > targetAspectRatio {
                xRatio = 1.0
                yRatio = Float((fromSize.height / toSize.height) * (toSize.width / fromSize.width))
            } else {
                xRatio = Float((toSize.height / fromSize.height) * (fromSize.width / toSize.width))
                yRatio = 1.0
            }
        case .aspectFill:
            if aspectRatio > targetAspectRatio {
                xRatio = Float((fromSize.width / toSize.width) * (toSize.height / fromSize.height))
                yRatio = 1.0
            } else {
                xRatio = 1.0
                yRatio = Float((fromSize.height / toSize.height) * (toSize.width / fromSize.width))
            }
        }

        var result = vertices

        for i in 0..<result.count {
            if i % 2 == 0 {
                result[i] = result[i] * xRatio
            } else {
                result[i] = result[i] * yRatio
            }
        }

        return result
    }
}

public class RenderView: View, ImageConsumer {
    public var inputTexture: MTLTexture?
    private(set) public var outputTexture: MTLTexture?
    
    private let metalLayer: CAMetalLayer = CAMetalLayer()

    private var renderPipelineState: MTLRenderPipelineState?

    private var indexBuffer: MTLBuffer!
    private var vertexBuffer: MTLBuffer!
    private var textureBuffer: MTLBuffer!

    private var metalContext: MetalContext?

    private var outputSize: CGSize = .zero

    public var fillMode: FillMode = .stretch

    public var context: MetalContext? {
        set {
            guard let context = newValue else {
                return
            }

            metalContext = context

            metalLayer.device = context.device

            do {
                renderPipelineState = try context.createRenderPipeline(vertexFunctionName: "basic_vertex", fragmentFunctionName: "basic_fragment")
            } catch {
                Log("Could not create render pipeline state.")
            }

            indexBuffer = context.buffer(array: Static.indexData)
            vertexBuffer = context.buffer(array: Static.vertexData)
            textureBuffer = context.buffer(array: Static.TextureRotation.none.rotation())
        }

        get {
            return metalContext
        }
    }

    public convenience init(frame: CGRect, context: MetalContext) {
        self.init(frame: frame)

        self.context = context
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    private func commonInit() {
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.frame = bounds

        #if os(iOS)
            metalLayer.contentsScale = UIScreen.main.scale
            layer.addSublayer(metalLayer)
        #elseif os(OSX)
            layer = metalLayer

            if let scale = NSScreen.main?.backingScaleFactor {
                metalLayer.contentsScale = scale
            }
        #endif
    }

    public func newFrameReady(at time: CMTime, at index: Int, using buffer: MTLCommandBuffer) {
        if let drawable = metalLayer.nextDrawable() {
            let size = metalLayer.bounds.size

            if outputSize != size {
                outputSize = size
                updateTextureCoordinates()
            }

            displayWithCommandBuffer(buffer: buffer, outputTexture: drawable.texture)
            buffer.present(drawable)
        }

        buffer.commit()
    }

    private func updateTextureCoordinates() {
        guard let height = inputTexture?.height, let width = inputTexture?.width else {
            return
        }

        let content: [Float] = Static.vertexData

        let inputSize = CGSize(width: width, height: height)
        let alteredVertexCoordinates = fillMode.convert(vertices: content, fromSize: inputSize, toSize: outputSize)
        vertexBuffer.contents().copyBytes(from: alteredVertexCoordinates, count: content.count * MemoryLayout<Float>.stride)
    }

    private func displayWithCommandBuffer(buffer: MTLCommandBuffer, outputTexture: MTLTexture) {
        if let renderPipelineState = renderPipelineState {
            let renderPassDescriptor = configureRenderPassDescriptor(texture: outputTexture)
            guard let renderCommandEncoder = buffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
                return
            }

            renderCommandEncoder.pushDebugGroup("Base Filter Render Encoder")
            renderCommandEncoder.setFragmentTexture(inputTexture, index: 0)
            renderCommandEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            renderCommandEncoder.setVertexBuffer(textureBuffer, offset: 0, index: 1)

            renderCommandEncoder.setRenderPipelineState(renderPipelineState)

            renderCommandEncoder.drawIndexedPrimitives(type: .triangle, indexCount: 6, indexType: .uint16, indexBuffer: indexBuffer, indexBufferOffset: 0)

            renderCommandEncoder.endEncoding()

            renderCommandEncoder.popDebugGroup()
        }
    }

    private func configureRenderPassDescriptor(texture: MTLTexture?) -> MTLRenderPassDescriptor {
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0)
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        return renderPassDescriptor
    }
}
