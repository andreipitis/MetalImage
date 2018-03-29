//
//  MovieInput.swift
//  MetalImage
//
//  Created by Andrei-Sergiu Pițiș on 02/07/2017.
//  Copyright © 2017 Andrei-Sergiu Pițiș. All rights reserved.
//

import Foundation
import AVFoundation
import Accelerate

//This will be passed by reference, but Swift structs are passed by value, hence the class qualifier.
private class AudioStructure {
    var instance: MovieInput?
    var audioFormat: AudioStreamBasicDescription?
}

public enum PlaybackOptions {
    case none
    case playAtactualSpeed
    case playAtactualSpeedAndLoopIndefinetely
}

public class MovieInput: ImageSource {
    public var targets: [ImageConsumer] = []
    
    fileprivate(set) public var outputTexture: MTLTexture?
    fileprivate var frameTime: CMTime = kCMTimeZero

    private let asset: AVURLAsset
    private var assetReader: AVAssetReader?
    private let assetReaderQueue: DispatchQueue = DispatchQueue.global(qos: .background)

    private let context: MetalContext
    private let metalTextureCache: CVMetalTextureCache

    //Used for playback at actual speed
    private var endRecordingTime: CMTime = kCMTimeZero
    private var playerItem: AVPlayerItem?
    private var player: AVQueuePlayer?
    private var itemVideoOutput: AVPlayerItemVideoOutput?

    private let playbackOptions: PlaybackOptions

    private lazy var displayLink = DisplayLink { (displayLink, timestamp) in
        self.render(displayLink: displayLink, timestamp: timestamp)
    }

    private var completionCallback: (() -> Void)?
    private(set) var isRunning: Bool = false

    public weak var audioEncodingTarget: AudioEncodingTarget? {
        didSet {
            audioEncodingTarget?.enableAudio()
        }
    }

    public init?(url: URL, playbackOptions: PlaybackOptions = .none, context: MetalContext) {
        guard let textureCache = context.textureCache() else {
            Logger.error("Could not create texture cache")
            return nil
        }

        self.metalTextureCache = textureCache
        self.context = context

        asset = AVURLAsset(url: url)

        self.playbackOptions = playbackOptions

        let videoTracks = asset.tracks(withMediaType: .video)
        let audioTracks = asset.tracks(withMediaType: .audio)

        if playbackOptions != .none  {
            player = AVQueuePlayer()
            playerItem = AVPlayerItem(asset: asset)

            let attributes = [kCVPixelBufferPixelFormatTypeKey as String : Int(kCVPixelFormatType_32BGRA)]
            itemVideoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: attributes)

            playerItem?.add(itemVideoOutput!)
            configureRealtimePlaybackAudio(audioTracks: audioTracks, playerItem: &playerItem!)

            NotificationCenter.default.addObserver(self, selector: #selector(finishedItemPlayback(notification:)), name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
            player?.replaceCurrentItem(with: playerItem)

            let itemCopy = playerItem?.copy() as! AVPlayerItem
            player?.insert(itemCopy, after: playerItem!)

            if playbackOptions == .playAtactualSpeedAndLoopIndefinetely {
                player?.actionAtItemEnd = AVPlayerActionAtItemEnd.advance
            } else {
                player?.actionAtItemEnd = AVPlayerActionAtItemEnd.pause
            }
        } else {
            do {
                try assetReader = AVAssetReader(asset: asset)
            } catch {
                Logger.error("Could not create asset reader for asset")
                return nil
            }

            setupAudio(audioTracks: audioTracks, for: assetReader!)
            setupVideo(videoTracks: videoTracks, for: assetReader!)
        }
    }

    deinit {
        completionCallback = nil
        NotificationCenter.default.removeObserver(self)
        Logger.debug("Deinit Movie Input")
    }

    public func start(completion: (() -> Void)?) {
        guard isRunning == false else {
            Logger.warning("Movie reader is already running")
            return
        }

        isRunning = true

        if playbackOptions != .none {
            completionCallback = completion
            player?.play()

            displayLink.start()
        } else {
            asset.loadValuesAsynchronously(forKeys: ["duration", "tracks"]) { [weak self] in
                guard let strongSelf = self, let assetReader = strongSelf.assetReader else {
                    return
                }

                var videoOutput: AVAssetReaderOutput?
                var audioOutput: AVAssetReaderOutput?

                for output in assetReader.outputs {
                    if output.mediaType == AVMediaType.video.rawValue {
                        videoOutput = output
                    }

                    if output.mediaType == AVMediaType.audio.rawValue {
                        audioOutput = output
                    }
                }

                DispatchQueue.global(qos: .default).async {
                    var error: NSError?
                    guard strongSelf.asset.statusOfValue(forKey: "tracks", error: &error) == .loaded else {
                        Logger.error("Could not load tracks. Error = \(String(describing: error))")
                        return
                    }

                    guard assetReader.startReading() == true else {
                        Logger.error("Could not start asset reader")
                        return
                    }

                    reading: while assetReader.status == .reading {
                        autoreleasepool {
                            if let _ = strongSelf.audioEncodingTarget {
                                if let sampleBuffer = videoOutput?.copyNextSampleBuffer() {
                                    strongSelf.readNextVideoFrame(sampleBuffer: sampleBuffer)
                                }

                                if let sampleBuffer = audioOutput?.copyNextSampleBuffer() {
                                    strongSelf.readNextAudioFrame(sampleBuffer: sampleBuffer)
                                }
                            } else if let sampleBuffer = videoOutput?.copyNextSampleBuffer() {
                                strongSelf.readNextVideoFrame(sampleBuffer: sampleBuffer)
                            } else {
                                assetReader.cancelReading()
                            }
                        }
                    }

                    if assetReader.status == .completed || assetReader.status == .cancelled {
                        strongSelf.isRunning = false
                        assetReader.cancelReading()
                        completion?()
                    }
                }
            }
        }
    }

    public func stop() {
        guard isRunning == true else {
            Logger.warning("Movie reader already stopped running")
            return
        }

        isRunning = false

        if playbackOptions != .none {

            player?.pause()

            displayLink.stop()
        } else {
            assetReader?.cancelReading()
        }
    }

    //MTAudioProcessingTap implementation
    private let tapInit: MTAudioProcessingTapInitCallback = {
        (tap, clientInfo, tapStorageOut) in
        guard let clientInfo = clientInfo else {
            return
        }

        let pointerToSelf = Unmanaged<MovieInput>.fromOpaque(clientInfo)
        let objectSelf = pointerToSelf.takeRetainedValue()

        let audioStructurePointer = calloc(1, MemoryLayout<AudioStructure>.size)
        audioStructurePointer?.initializeMemory(as: AudioStructure.self, to: AudioStructure())

        var structure: AudioStructure? = audioStructurePointer?.bindMemory(to: AudioStructure.self, capacity: 1).pointee
        structure?.instance = objectSelf

        tapStorageOut.pointee = audioStructurePointer
    }

    private let tapFinalize: MTAudioProcessingTapFinalizeCallback = {
        (tap) in

        let storage = MTAudioProcessingTapGetStorage(tap)

        free(storage)
        Logger.info("Audio tap finalized")
    }

    private let tapPrepare: MTAudioProcessingTapPrepareCallback = {
        (tap, itemCount, streamDescription) in

        var structure: AudioStructure = MTAudioProcessingTapGetStorage(tap).bindMemory(to: AudioStructure.self, capacity: 1).pointee
        structure.audioFormat = streamDescription.pointee

        Logger.info("Audio tap prepared")
    }

    private var tapUnprepare: MTAudioProcessingTapUnprepareCallback = {
        (tap) in
        Logger.info("Audio tap unprepared")
    }

    private var tapProcess: MTAudioProcessingTapProcessCallback = {
        (tap, numberFrames, flags, bufferListInOut, numberFramesOut, flagsOut) in
        let status = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut)

        guard status == 0 else {
            return
        }

        var structure: AudioStructure = MTAudioProcessingTapGetStorage(tap).bindMemory(to: AudioStructure.self, capacity: 1).pointee

        if var format = structure.audioFormat, let object = structure.instance {
            object.processAudioData(audioData: bufferListInOut, framesNumber: numberFrames, audioFormat: &format)
        }
    }

    private func configureRealtimePlaybackAudio(audioTracks: [AVAssetTrack], playerItem: inout AVPlayerItem) {
        let rawPointerSelf = Unmanaged.passUnretained(self).toOpaque()

        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: rawPointerSelf,
            init: tapInit,
            finalize: tapFinalize,
            prepare: tapPrepare,
            unprepare: tapUnprepare,
            process: tapProcess)

        var tap: Unmanaged<MTAudioProcessingTap>?
        let err = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap)

        if err == noErr {
        }

        var inputParameters: [AVMutableAudioMixInputParameters] = []

        for track in audioTracks {
            let parameter = AVMutableAudioMixInputParameters(track: track)
            parameter.audioTapProcessor = tap?.takeUnretainedValue()

            inputParameters.append(parameter)
        }

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = inputParameters

        playerItem.audioMix = audioMix

        _ = tap?.autorelease()
    }
    //MTAudioProcessingTap implementation end

    @objc private func finishedItemPlayback(notification: Notification) {
        guard let player = player, let lastItem = player.items().last else {
            return
        }

        let itemCopy = lastItem.copy() as! AVPlayerItem
        player.currentItem?.remove(itemVideoOutput!)
        lastItem.add(itemVideoOutput!)
        player.insert(itemCopy, after: lastItem)

        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
        NotificationCenter.default.addObserver(self, selector: #selector(finishedItemPlayback(notification:)), name: .AVPlayerItemDidPlayToEndTime, object: lastItem)

        playerItem = lastItem

        endRecordingTime = frameTime
        if playbackOptions != .playAtactualSpeedAndLoopIndefinetely {
            displayLink.stop()

            player.advanceToNextItem()
            isRunning = false
            completionCallback?()
        }
    }


    private func render(displayLink: MIDisplayLink, timestamp: MITimestamp) {
        guard let videoOutput = itemVideoOutput else {
            return
        }
        //TODO: Compare timestamps for iOS and OSX and figure out how to remove the OS checks
        #if os(iOS)
            let nextVsync: CFTimeInterval = timestamp + displayLink.duration
            let currentTime = videoOutput.itemTime(forHostTime: nextVsync)

            if videoOutput.hasNewPixelBuffer(forItemTime: currentTime), let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: currentTime, itemTimeForDisplay: nil) {
                readNextImage(pixelBuffer: pixelBuffer, at: currentTime)
            }
        #elseif os(OSX)
            var currentTime = kCMTimeInvalid
            let nextVSync = timestamp
            currentTime = videoOutput.itemTime(for: nextVSync)
            frameTime = CMTimeAdd(currentTime, endRecordingTime)

            if videoOutput.hasNewPixelBuffer(forItemTime: currentTime), let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: currentTime, itemTimeForDisplay: nil) {
                readNextImage(pixelBuffer: pixelBuffer, at: frameTime)
            }
        #endif
    }

    private func readNextImage(pixelBuffer: CVImageBuffer, at frameTime: CMTime) {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var cvMetalTexture: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, metalTextureCache, pixelBuffer, nil, .bgra8Unorm, width, height, 0, &cvMetalTexture)

        guard result == kCVReturnSuccess else {
            Logger.error("Failed to get Metal texture from pixel buffer")
            return
        }

        let metalTexture = CVMetalTextureGetTexture(cvMetalTexture!)

        outputTexture = metalTexture

        autoreleasepool {
            for var target in targets {
                let commandBuffer = context.newCommandBuffer()

                target.inputTexture = metalTexture
                target.newFrameReady(at: frameTime, at: 0, using: commandBuffer)
            }
        }
    }

    private func readNextVideoFrame(sampleBuffer: CMSampleBuffer) {
        assetReaderQueue.sync { [weak self] in
            guard let strongSelf = self else {
                return
            }

            guard let pixelBuffer: CVImageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                Logger.error("Could not get pixel buffer.")
                return
            }

            strongSelf.frameTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

            strongSelf.readNextImage(pixelBuffer: pixelBuffer, at: strongSelf.frameTime)
        }
    }

    private func readNextAudioFrame(sampleBuffer: CMSampleBuffer?) {
        assetReaderQueue.sync {
            audioEncodingTarget?.processAudio(sampleBuffer)
        }
    }

    private func processAudioData(audioData: UnsafeMutablePointer<AudioBufferList>, framesNumber: CMItemCount, audioFormat: UnsafePointer<AudioStreamBasicDescription>) {
        var sampleBuffer: CMSampleBuffer?
        var status: OSStatus?
        var format: CMFormatDescription?

        status = CMAudioFormatDescriptionCreate(kCFAllocatorDefault, audioFormat, 0, nil, 0, nil, nil, &format)
        if status != noErr {
            Logger.error("Error CMAudioFormatDescriptionCreater :\(String(describing: status))")
            return
        }

        var timing = CMSampleTimingInfo(duration: CMTimeMake(1, Int32(audioFormat.pointee.mSampleRate)), presentationTimeStamp: kCMTimeZero, decodeTimeStamp: kCMTimeInvalid)

        status = CMSampleBufferCreate(kCFAllocatorDefault, nil, false, nil, nil, format, framesNumber, 1, &timing, 0, nil, &sampleBuffer)

        if status != noErr {
            Logger.error("Error CMSampleBufferCreate :\(String(describing: status))")
            return
        }

        status = CMSampleBufferSetDataBufferFromAudioBufferList(sampleBuffer!, kCFAllocatorDefault , kCFAllocatorDefault, 0, audioData)
        if status != noErr {
            Logger.error("Error CMSampleBufferSetDataBufferFromAudioBufferList :\(String(describing: status))")
            return
        }

        readNextAudioFrame(sampleBuffer: sampleBuffer)
    }

    private func setupAudio(audioTracks: [AVAssetTrack], for reader: AVAssetReader) {
        guard audioTracks.count > 0 else {
            Logger.info("The asset does not have any audio tracks")
            return
        }

        let audioSettings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM]

        let audioTrackOutput = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: audioSettings)//AVAssetReaderTrackOutput(track: audioTrack, outputSettings: audioSettings)

        audioTrackOutput.alwaysCopiesSampleData = false

        if reader.canAdd(audioTrackOutput) {
            reader.add(audioTrackOutput)
        } else {
            Logger.error("Could not add audio output to reader")
        }
    }

    private func setupVideo(videoTracks: [AVAssetTrack], for reader: AVAssetReader) {
        guard let videoTrack = videoTracks.first else {
            Logger.info("The asset does not have any video tracks")
            return
        }
        
        let videoSettings: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        
        let videoTrackOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: videoSettings)
        
        videoTrackOutput.alwaysCopiesSampleData = false
        
        if reader.canAdd(videoTrackOutput) {
            reader.add(videoTrackOutput)
        } else {
            Logger.error("Could not add video output to reader")
        }
    }
}
