//
//  Camera.swift
//  MetalImage
//
//  Created by Andrei-Sergiu Pițiș on 28/06/2017.
//  Copyright © 2017 Andrei-Sergiu Pițiș. All rights reserved.
//

import Foundation
import AVFoundation

public class Camera: NSObject, ImageSource {
    public var targets: [ImageConsumer] = []

    fileprivate(set) public var outputTexture: MTLTexture?

    private let context: MetalContext
    
    fileprivate var frameTime: CMTime = kCMTimeInvalid

    private let captureSession: AVCaptureSession = AVCaptureSession()

    private let videoProcessingQueue = DispatchQueue(label: "videoProcessingQueue", qos: .default)
    private let audioProcessingQueue = DispatchQueue(label: "audioProcessingQueue", qos: .default)

    fileprivate let metalTextureCache: CVMetalTextureCache

    private lazy var displayLink = DisplayLink { (displayLink, timestamp) in
        self.render()
    }

    public weak var audioEncodingTarget: AudioEncodingTarget? {
        didSet {
            audioEncodingTarget?.enableAudio()
        }
    }

    public init?(preferredCaptureDevice: AVCaptureDevice.Position = .back, context: MetalContext) {
        guard let textureCache = context.textureCache() else {
            Log.error("Could not create texture cache")
            return nil
        }

        self.metalTextureCache = textureCache
        self.context = context

        super.init()

        captureSession.beginConfiguration()

        #if os(iOS)
            let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .builtInMicrophone], mediaType: .video, position: preferredCaptureDevice).devices
        #elseif os(OSX)
            let devices = AVCaptureDevice.devices()
        #endif

        var videoDevice: AVCaptureDevice?
        var audioDevice: AVCaptureDevice?

        for device in devices {
            if device.hasMediaType(.video) && device.position == preferredCaptureDevice && videoDevice == nil {
                videoDevice = device
            }

            if device.hasMediaType(.audio) && audioDevice == nil {
                audioDevice = device
            }
        }

        if videoDevice == nil {
            videoDevice = AVCaptureDevice.default(for: .video)
        }

        if audioDevice == nil {
            audioDevice = AVCaptureDevice.default(for: .audio)
        }

        guard let finalVideoDevice = videoDevice, let finalAudioDevice = audioDevice else {
            Log.error("Failed to get video or audio device")
            return
        }

        // On OSX there seems to be a weird memory leak associated with the video input. Not sure why this is happening yet.
        addInput(finalVideoDevice)
        addInput(finalAudioDevice)

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.alwaysDiscardsLateVideoFrames = true

        #if os(iOS)
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCMPixelFormat_32BGRA]
        #elseif os(OSX)
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCMPixelFormat_32BGRA,
                                         kCVPixelBufferMetalCompatibilityKey as String: true]
        #endif

        videoOutput.setSampleBufferDelegate(self, queue: videoProcessingQueue)

        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        } else {
            Log.error("Could not add video output to capture session.")
        }

        let audioOutput = AVCaptureAudioDataOutput()
        #if os(OSX)
            audioOutput.audioSettings = [AVFormatIDKey: kAudioFormatMPEG4AAC,
                                         AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue]
        #endif

        audioOutput.setSampleBufferDelegate(self, queue: audioProcessingQueue)

        if captureSession.canAddOutput(audioOutput) {
            captureSession.addOutput(audioOutput)
        } else {
            Log.error("Could not add audio output to capture session.")
        }

        captureSession.commitConfiguration()

        if let videoConnection = videoOutput.connection(with: .video) {
            if videoConnection.isVideoOrientationSupported {
                videoConnection.videoOrientation = .portrait
            }

            if videoDevice?.position == .front, videoConnection.isVideoMirroringSupported == true {
                videoConnection.isVideoMirrored = true
            }
        }
    }

    deinit {
        displayLink.invalidate()

        for input in captureSession.inputs {
            captureSession.removeInput(input)
        }

        Log.debug("Deinit Camera")
    }

    public func start() {
        captureSession.startRunning()
        displayLink.start()
    }

    public func stop() {
        captureSession.stopRunning()

        displayLink.stop()
    }

    @objc func render() {
        autoreleasepool {
            if let texture = outputTexture {
                for var target in targets {
                    let commandBuffer = context.newCommandBuffer()

                    target.inputTexture = texture
                    target.newFrameReady(at: frameTime, at: 0, using: commandBuffer)
                }
            }
        }
    }

    private func addInput(_ device: AVCaptureDevice) {
        do {
            let input = try AVCaptureDeviceInput(device: device)

            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            } else {
                Log.error("Could not add input: \(input).")
            }
        } catch {
            Log.error("Failed to retrieve input for device: \(device)")
        }
    }
}

extension Camera: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    public func captureOutput(_ captureOutput: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
//        Log("Dropped a video frame")
    }

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        autoreleasepool {
            if output is AVCaptureVideoDataOutput {
                if let pixelBuffer: CVPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                    let width = CVPixelBufferGetWidth(pixelBuffer)
                    let height = CVPixelBufferGetHeight(pixelBuffer)

                    var cvMetalTexture: CVMetalTexture?
                    let result = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, metalTextureCache, pixelBuffer, nil, .bgra8Unorm, width, height, 0, &cvMetalTexture)

                    guard result == kCVReturnSuccess else {
                        Log.error("Failed to get metal texture from pixel buffer")
                        return
                    }
                    
                    let metalTexture = CVMetalTextureGetTexture(cvMetalTexture!)
                    
                    outputTexture = metalTexture

                    frameTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                }
            } else {
                audioEncodingTarget?.processAudio(sampleBuffer)
            }
        }
    }
}
