//
//  MetalDevice.swift
//  MetalImage
//
//  Created by Andrei-Sergiu Pițiș on 06/06/2017.
//  Copyright © 2017 Andrei-Sergiu Pițiș. All rights reserved.
//

import Foundation
import AVFoundation
import Metal

public enum MetalDeviceError: Error {
    case failedToCreateFunction(name: String)
    case failedToCreateDevice(details: String)
}

public enum DeviceType {
    case lowPower
    case highPower
}

public class MetalContext {
    private let renderPipelineCache = NSCache<NSString, AnyObject>()
    private let computePipelineCache = NSCache<NSString, AnyObject>()

    internal let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let defaultLibrary: MTLLibrary

    public init(device: MTLDevice) throws {
        guard let queue = device.makeCommandQueue() else {
            throw MetalDeviceError.failedToCreateDevice(details: "Could not create CommandQueue.")
        }

        guard let library = device.makeDefaultLibrary() else {
            throw MetalDeviceError.failedToCreateDevice(details: "Could not create DefaultLibrary.")
        }

        self.device = device
        self.commandQueue = queue
        self.defaultLibrary = library
    }

    public convenience init(preferredDevice: DeviceType) throws {
        #if os(OSX)
        let devices = MTLCopyAllDevices()

        switch preferredDevice {
        case .highPower:
            if let highPowerDevice = devices.first(where: { (device) -> Bool in
                return device.isLowPower == false
            }) {
                try self.init(device: highPowerDevice)
                return
            }
        case .lowPower:
            if let lowPowerDevice = devices.first(where: { (device) -> Bool in
                return device.isLowPower == true
            }) {
                try self.init(device: lowPowerDevice)
                return
            }
        }
        #endif

        //Fallback to default device
        if let defaultDevice = MTLCreateSystemDefaultDevice() {
            try self.init(device: defaultDevice)
        } else {
            throw MetalDeviceError.failedToCreateDevice(details: "No device available.")
        }
    }

    //Create buffer methods

    public func buffer<T>(array: Array<T>) -> MTLBuffer {
        let size = array.count * MemoryLayout.size(ofValue: array[0])
        return device.makeBuffer(bytes: array, length: size, options: [])!
    }

    public func buffer<T>(data: inout T) -> MTLBuffer {
        let size = MemoryLayout.stride(ofValue: data)
        return device.makeBuffer(bytes: &data, length: size, options: [])!
    }

    func createTexture(descriptor: MTLTextureDescriptor) -> MTLTexture {
        return device.makeTexture(descriptor: descriptor)!
    }

    func textureCache() -> CVMetalTextureCache? {
        var metalTextureCache: CVMetalTextureCache?

        let result: CVReturn = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &metalTextureCache)

        guard result == kCVReturnSuccess, let textureCache = metalTextureCache else {
            Log("Could not create texture cache")
            return nil
        }

        CVMetalTextureCacheFlush(textureCache, 0)

        return textureCache
    }

    //Create command buffer
    public func newCommandBuffer() -> MTLCommandBuffer {
        return commandQueue.makeCommandBuffer()!
    }

    //Create pipelines
    public func createRenderPipeline(vertexFunctionName: String = "basicVertexFunction", fragmentFunctionName: String) throws -> MTLRenderPipelineState {
        let cacheKey = NSString(string: vertexFunctionName + fragmentFunctionName)
        
        if let pipelineState = renderPipelineCache.object(forKey: cacheKey) as? MTLRenderPipelineState {
            return pipelineState
        }
        
        guard let vertexFunction = defaultLibrary.makeFunction(name: vertexFunctionName) else {
            throw MetalDeviceError.failedToCreateFunction(name: vertexFunctionName)
        }
        
        guard let fragmentFunction = defaultLibrary.makeFunction(name: fragmentFunctionName) else {
            throw MetalDeviceError.failedToCreateFunction(name: fragmentFunctionName)
        }
        
        let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineStateDescriptor.vertexFunction = vertexFunction
        pipelineStateDescriptor.fragmentFunction = fragmentFunction
        
        let pipelineState = try device.makeRenderPipelineState(descriptor: pipelineStateDescriptor)
        
        renderPipelineCache.setObject(pipelineState, forKey: cacheKey)
        
        return pipelineState
    }
    
    public func createComputePipeline(computeFunctionName: String) throws -> MTLComputePipelineState {
        let cacheKey = NSString(string: computeFunctionName)
        
        if let pipelineState = computePipelineCache.object(forKey: cacheKey) as? MTLComputePipelineState {
            return pipelineState
        }
        
        guard let computeFunction = defaultLibrary.makeFunction(name: computeFunctionName) else {
            throw MetalDeviceError.failedToCreateFunction(name: computeFunctionName)
        }
        
        let pipelineState =  try device.makeComputePipelineState(function: computeFunction)
        
        computePipelineCache.setObject(pipelineState, forKey: cacheKey)
        
        return pipelineState
    }
}
