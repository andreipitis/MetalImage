//
//  MovieOutput.swift
//  MetalImage
//
//  Created by Andrei-Sergiu Pițiș on 30/06/2017.
//  Copyright © 2017 Andrei-Sergiu Pițiș. All rights reserved.
//

import Foundation
import AVFoundation
import Metal

public protocol AudioEncodingTarget: class {
    func enableAudio()
    func processAudio(_ sampleBuffer: CMSampleBuffer?)
}

struct VideoData {
    let sampleBuffer: CVPixelBuffer
    let presentationTime: CMTime
}

public class MovieOutput: ImageConsumer, AudioEncodingTarget {
    public var inputTexture: MTLTexture?
    private(set) public var outputTexture: MTLTexture?
    
    private let videoQueue = AtomicQueue<VideoData>()
    private let audioQueue = AtomicQueue<CMSampleBuffer>()

    private var isRecording: Bool = false

    private let assetWriter: AVAssetWriter
    private let assetWriterVideoInput: AVAssetWriterInput
    private let assetWriterAudioInput: AVAssetWriterInput
    private let assetWriterPixelBufferInput: AVAssetWriterInputPixelBufferAdaptor

    private let synchronousQueue: DispatchQueue = DispatchQueue.global(qos: .background)
    private let assetProcessingQueue: DispatchQueue = DispatchQueue(label: "serialQueue")

    private let liveVideo: Bool
    private var firstAudioSample: Bool = true
    
    private var recordingStartTime: CMTime?
    private var previousTime: CMTime = kCMTimeInvalid

    private var renderPipelineState: MTLRenderPipelineState?

    private let indexBuffer: MTLBuffer
    private let vertexBuffer: MTLBuffer
    private let textureBuffer: MTLBuffer

    public init?(url: URL, size: CGSize, fileType: AVFileType = AVFileType.mov, liveVideo: Bool = false, optimizeForNetworkUse: Bool = true, context: MetalContext) {
        self.liveVideo = liveVideo

        do {
            assetWriter = try AVAssetWriter(outputURL: url, fileType: fileType)
        } catch {
            return nil
        }

        assetWriter.shouldOptimizeForNetworkUse = optimizeForNetworkUse

        let videoOutputSettings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.h264,
                                                  AVVideoWidthKey: size.width,
                                                  AVVideoHeightKey: size.height]

        assetWriterVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoOutputSettings)
        assetWriterVideoInput.expectsMediaDataInRealTime = liveVideo

        #if os(iOS)
            let audioOutputSettings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM,
                                                  AVNumberOfChannelsKey: 1,
                                                  AVSampleRateKey: 44100.0,
                                                  AVLinearPCMIsBigEndianKey: true,
                                                  AVLinearPCMIsFloatKey: false,
                                                  AVLinearPCMIsNonInterleaved: false,
                                                  AVLinearPCMBitDepthKey: 32]

            assetWriterAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioOutputSettings)
        #elseif os(OSX)
            assetWriterAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
        #endif
        assetWriterAudioInput.expectsMediaDataInRealTime = liveVideo

        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: size.width,
            kCVPixelBufferHeightKey as String: size.height]

        assetWriterPixelBufferInput = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: assetWriterVideoInput, sourcePixelBufferAttributes: sourcePixelBufferAttributes)

        assetWriter.add(assetWriterVideoInput)

        do {
            renderPipelineState = try context.createRenderPipeline(vertexFunctionName: "basic_vertex", fragmentFunctionName: "basic_fragment")
        } catch {
            Log.error("Could not create render pipeline state.")
        }

        indexBuffer = context.buffer(array: Static.indexData)
        vertexBuffer = context.buffer(array: Static.vertexData)
        textureBuffer = context.buffer(array: Static.TextureRotation.none.rotation())

        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.pixelFormat = .bgra8Unorm
        textureDescriptor.usage = [.shaderRead, .renderTarget, .shaderWrite]
        
        textureDescriptor.width = Int(size.width)
        textureDescriptor.height = Int(size.height)
        outputTexture = context.createTexture(descriptor: textureDescriptor)
    }

    deinit {
        Log.debug("Deinit Movie Output")
    }

    public func startRecording() {
        guard isRecording == false else {
            Log.warning("Tried to start an already running recording.")
            return
        }
        assetWriter.startWriting()

        isRecording = true
    }

    public func endRecording(_ completionHandler: @escaping () -> ()) {
        guard isRecording == true else {
            Log.warning("Tried to stop an already stopped recording.")
            return
        }

        isRecording = false

        if assetWriter.inputs.contains(assetWriterAudioInput) {
            assetWriterAudioInput.markAsFinished()
        }

        assetWriterVideoInput.markAsFinished()

        assetWriter.finishWriting(completionHandler: completionHandler)

        videoQueue.emptyQueue()
        audioQueue.emptyQueue()
    }

    public func enableAudio() {
        assetWriter.add(assetWriterAudioInput)
    }

    public func startHandlers() {
        if assetWriter.inputs.contains(assetWriterAudioInput) {
            assetWriterAudioInput.requestMediaDataWhenReady(on: assetProcessingQueue) { [weak self] in
                guard let strongSelf = self else {
                    return
                }

                guard strongSelf.assetWriter.status == .writing else {
                    return
                }

                if strongSelf.assetWriterAudioInput.isReadyForMoreMediaData == false {
                    strongSelf.assetWriterAudioInput.markAsFinished()

                    Log.debug("Audio writer can not take any more data.")
                    return
                }

                if let item = strongSelf.audioQueue.dequeue() {
                    strongSelf.assetWriterAudioInput.append(item)
                }
            }
        }
        assetWriterVideoInput.requestMediaDataWhenReady(on: assetProcessingQueue) { [weak self] in
            guard let strongSelf = self else {
                return
            }

            guard strongSelf.assetWriter.status == .writing else {
                return
            }

            if strongSelf.assetWriterVideoInput.isReadyForMoreMediaData == false {
                strongSelf.assetWriterVideoInput.markAsFinished()

                Log.debug("Video writer can not take any more data.")
                return
            }

            if let item = strongSelf.videoQueue.dequeue() {
                if strongSelf.assetWriterPixelBufferInput.append(item.sampleBuffer, withPresentationTime: item.presentationTime) == false {
                    Log.error("Error appending pixel buffer")
                }
            }
        }
    }

    public func processAudio(_ sampleBuffer: CMSampleBuffer?) {
        guard isRecording == true else {
            return
        }

        guard assetWriter.status != .failed else {
            Log.error("Error, AVWriter failed: \(String(describing: assetWriter.error))")
            return
        }

        guard let audioSampleBuffer = sampleBuffer else {
            assetWriterAudioInput.markAsFinished()
            return
        }

        synchronousQueue.sync {
            let currentSampleTime = CMSampleBufferGetPresentationTimeStamp(audioSampleBuffer)

            //TODO: The samples do not seem to be trimmed correctly need to investigate further.
            #if os(OSX)
                if liveVideo == true && firstAudioSample == true {
                    firstAudioSample = false
                    //Fixes a crash for OSX. There is a an encoder delay of 2112 samples for AAC sound.
                    let dict = CMTimeCopyAsDictionary(CMTimeMake(2112, currentSampleTime.timescale), kCFAllocatorDefault)
                    CMSetAttachment(audioSampleBuffer, kCMSampleBufferAttachmentKey_TrimDurationAtStart, dict, kCMAttachmentMode_ShouldNotPropagate)
                }
            #endif

            if recordingStartTime == nil {
                if assetWriter.status != .writing {
                    assetWriter.startWriting()
                }

                assetWriter.startSession(atSourceTime: currentSampleTime)
                recordingStartTime = currentSampleTime

                self.startHandlers()
            }

            audioQueue.enqueue(item: audioSampleBuffer)
        }
    }

    public func newFrameReady(at time: CMTime, at index: Int, using buffer: MTLCommandBuffer) {
        guard isRecording == true else {
            buffer.commit()
            return
        }

        #if os(OSX)
            if liveVideo == true && (time.value == 0 || time.isValid == false) {
                buffer.commit()
                return
            }
        #endif

        if recordingStartTime == nil {
            if assetWriter.status != .writing {
                assetWriter.startWriting()
            }

            assetWriter.startSession(atSourceTime: time)
            recordingStartTime = time

            self.startHandlers()
        }

        renderWithCommandBuffer(buffer: buffer)
        buffer.commit()
        buffer.waitUntilCompleted()

        //Ensure video frames are saved synchronously.
        synchronousQueue.sync {
            //Pixel buffer pool becomes nil if we submit video frames with the same timestamp
            if previousTime >= time {
                previousTime = time
//                Log("Dropped a video frame")
                return
            }

            previousTime = time

            guard let pixelBufferPool = assetWriterPixelBufferInput.pixelBufferPool else {
                Log.error("Could not retrieve pixel buffer pool")
                return
            }

            var pixelBuffer: CVPixelBuffer?
            let result = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &pixelBuffer)

            guard result == kCVReturnSuccess, let finalPixelBuffer = pixelBuffer, let texture = outputTexture else {
                Log.error("Could not get a pixel buffer from the pool")
                return
            }

            CVPixelBufferLockBaseAddress(finalPixelBuffer, [])
            guard let pixelBufferBytes = CVPixelBufferGetBaseAddress(finalPixelBuffer) else {
                Log.error("Could not get pixel buffer bytes.")
                CVPixelBufferUnlockBaseAddress(finalPixelBuffer, [])

                return
            }

            let bytesPerRow = CVPixelBufferGetBytesPerRow(finalPixelBuffer)
            let region = MTLRegionMake2D(0, 0, texture.width, texture.height)

            texture.getBytes(pixelBufferBytes, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)

            let videoData = VideoData(sampleBuffer: finalPixelBuffer, presentationTime: time)
            videoQueue.enqueue(item: videoData)

            CVPixelBufferUnlockBaseAddress(finalPixelBuffer, [])
        }
    }

    private func updateTextureCoordinates() {
        guard let height = inputTexture?.height, let width = inputTexture?.width else {
            return
        }

        let content: [Float] = Static.vertexData

        let inputSize = CGSize(width: width, height: height)
        let outputSize = CGSize(width: outputTexture!.width, height: outputTexture!.height)
        let alteredVertexCoordinates = FillMode.aspectFit.convert(vertices: content, fromSize: inputSize, toSize: outputSize)
        vertexBuffer.contents().copyBytes(from: alteredVertexCoordinates, count: content.count * MemoryLayout<Float>.stride)
    }

    //Doing it this way instead of using a blit encoder ensures that an arbitrary sizes can be specified.
    private func renderWithCommandBuffer(buffer: MTLCommandBuffer) {
        updateTextureCoordinates()
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
        renderPassDescriptor.colorAttachments[0].loadAction = .dontCare
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0)
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        
        return renderPassDescriptor
    }
}
