//
//  BasicFilter.swift
//  MetalImage
//
//  Created by Andrei-Sergiu Pițiș on 19/05/2017.
//  Copyright © 2017 Andrei-Sergiu Pițiș. All rights reserved.
//

import Foundation
import CoreMedia
import Metal

struct PipelineStateConfiguration {
    let pixelFormat: MTLPixelFormat
    let vertexShader: String
    let fragmentShader: String
    let computeShader: String
}

public class BaseComputeFilter: ImageSource, ImageConsumer {
    public var targets: [ImageConsumer] = []

    public var inputTexture: MTLTexture?
    public private(set) var outputTexture: MTLTexture?

    private let context: MetalContext

    private var computePipelineState: MTLComputePipelineState?

    public init(computeShader: String, context: MetalContext) {
        let pipelineState = PipelineStateConfiguration(pixelFormat: .bgra8Unorm, vertexShader: "", fragmentShader: "", computeShader: computeShader)

        self.context = context

        configurePipeline(pipelineState: pipelineState, context: context)
    }

    deinit {
        Logger.debug("Deinit Base Compute Filter")
    }

    /**
     This methods will be called each frame. Make sure your implementation is as fast as possible as it may lead to slower performance of the pipeline.

     - Textures 0 and 1 are reserved for the input and output textures.
     */
    public func configure(computeEncoder: MTLComputeCommandEncoder) {
        assert(false, "Should be implemented by subclasses!")
    }

    public func newFrameReady(at time: CMTime, at index: Int, using buffer: MTLCommandBuffer) {
        autoreleasepool {
            var nextBuffer = buffer
            for var target in targets {
                calculateWithCommandBuffer(buffer: nextBuffer, target: &target, at: time)
                nextBuffer = context.newCommandBuffer()
            }
        }
    }

    private func calculateWithCommandBuffer(buffer: MTLCommandBuffer, target: inout ImageConsumer, at time: CMTime) {
        if outputTexture == nil {
            let textureDescriptor = MTLTextureDescriptor()
            textureDescriptor.pixelFormat = .bgra8Unorm
            textureDescriptor.usage = [.shaderRead, .renderTarget, .shaderWrite]
            textureDescriptor.width = inputTexture!.width
            textureDescriptor.height = inputTexture!.height
            outputTexture = buffer.device.makeTexture(descriptor: textureDescriptor)!
        }

        guard let computePipelineState = computePipelineState, let computeCommandEncoder = buffer.makeComputeCommandEncoder() else {
            return
        }

        computeCommandEncoder.pushDebugGroup("Base Compute Filter - Compute Encoder")
        computeCommandEncoder.setTexture(inputTexture, index: 0)
        computeCommandEncoder.setTexture(outputTexture, index: 1)

        configure(computeEncoder: computeCommandEncoder)

        computeCommandEncoder.setComputePipelineState(computePipelineState)

        let threadGroupCouts = MTLSize(width: 8, height: 8, depth: 1)
        let threadGroups = MTLSize(width: inputTexture!.width / threadGroupCouts.width, height: inputTexture!.height / threadGroupCouts.height, depth: 1)
        computeCommandEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCouts)

        computeCommandEncoder.endEncoding()
        computeCommandEncoder.popDebugGroup()

        target.inputTexture = outputTexture
        target.newFrameReady(at: time, at: 0, using: buffer)
    }

    private func configurePipeline(pipelineState: PipelineStateConfiguration, context: MetalContext) {
        guard computePipelineState == nil else {
            return
        }

        do {
            computePipelineState = try context.createComputePipeline(computeFunctionName: pipelineState.computeShader)
        } catch {
            Logger.error("Could not create compute pipeline state.")
        }
    }
}

public class BaseRenderFilter: ImageSource, ImageConsumer {
    public var targets: [ImageConsumer] = []
    
    public var inputTexture: MTLTexture?
    public private(set) var outputTexture: MTLTexture?

    private let context: MetalContext

    private var computePipelineState: MTLComputePipelineState?
    private var renderPipelineState: MTLRenderPipelineState?

    private var indexBuffer: MTLBuffer
    private var vertexBuffer: MTLBuffer
    private var textureBuffer: MTLBuffer

    public init(vertexShader: String, fragmentShader: String, context: MetalContext) {
        let pipelineState = PipelineStateConfiguration(pixelFormat: .bgra8Unorm, vertexShader: vertexShader, fragmentShader: fragmentShader, computeShader: "")

        self.context = context
        indexBuffer = context.buffer(array: Static.indexData)
        vertexBuffer = context.buffer(array: Static.vertexData)
        textureBuffer = context.buffer(array: Static.TextureRotation.none.rotation())

        configurePipeline(pipelineState: pipelineState, context: context)
    }

    deinit {
        Logger.debug("Deinit Base Render Filter")
    }

    /**
     This methods will be called each frame. Make sure your implementation is as fast as possible as it may lead to slower performance of the pipeline.

     - Vertex Buffers 0 and 1 are reserved for the vertices and texture coordinates.
     - Fragment Texture 0 is reserved for the input texture.
     */
    public func configure(renderEncoder: MTLRenderCommandEncoder) {
        assert(false, "Should be implemented by subclasses!")
    }

    public func newFrameReady(at time: CMTime, at index: Int, using buffer: MTLCommandBuffer) {
        autoreleasepool {
            var nextBuffer = buffer
            for var target in targets {
                calculateWithCommandBuffer(buffer: nextBuffer, target: &target, at: time)
                nextBuffer = context.newCommandBuffer()
            }
        }
    }

    private func calculateWithCommandBuffer(buffer: MTLCommandBuffer, target: inout ImageConsumer, at time: CMTime) {
        if outputTexture == nil {
            let textureDescriptor = MTLTextureDescriptor()
            textureDescriptor.pixelFormat = .bgra8Unorm
            textureDescriptor.usage = [.shaderRead, .renderTarget, .shaderWrite]
            textureDescriptor.width = inputTexture!.width
            textureDescriptor.height = inputTexture!.height
            outputTexture = buffer.device.makeTexture(descriptor: textureDescriptor)!
        }

        guard let renderPipelineState = renderPipelineState else {
            return
        }

        let renderPassDescriptor = configureRenderPassDescriptor(texture: outputTexture)
        guard let renderCommandEncoder = buffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        renderCommandEncoder.pushDebugGroup("Base Render Filter - Render Encoder")
        renderCommandEncoder.setFragmentTexture(inputTexture, index: 0)
        renderCommandEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderCommandEncoder.setVertexBuffer(textureBuffer, offset: 0, index: 1)

        configure(renderEncoder: renderCommandEncoder)

        renderCommandEncoder.setRenderPipelineState(renderPipelineState)

        renderCommandEncoder.drawIndexedPrimitives(type: .triangle, indexCount: 6, indexType: .uint16, indexBuffer: indexBuffer, indexBufferOffset: 0)

        renderCommandEncoder.endEncoding()

        renderCommandEncoder.popDebugGroup()

        target.inputTexture = outputTexture
        target.newFrameReady(at: time, at: 0, using: buffer)
    }

    private func configureRenderPassDescriptor(texture: MTLTexture?) -> MTLRenderPassDescriptor {
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = texture
        renderPassDescriptor.colorAttachments[0].loadAction = .dontCare
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0)
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        return renderPassDescriptor
    }

    private func configurePipeline(pipelineState: PipelineStateConfiguration, context: MetalContext) {
        guard renderPipelineState == nil else {
            return
        }

        do {
            renderPipelineState = try context.createRenderPipeline(vertexFunctionName: pipelineState.vertexShader, fragmentFunctionName: pipelineState.fragmentShader)
        } catch {
            Logger.error("Could not create render pipeline state.")
        }
    }
}
