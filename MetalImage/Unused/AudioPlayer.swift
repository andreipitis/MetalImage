//
//  AudioPlayer.swift
//  MetalImage
//
//  Created by Andrei-Sergiu Pițiș on 06/07/2017.
//  Copyright © 2017 Andrei-Sergiu Pițiș. All rights reserved.
//

import Foundation
import AVFoundation

fileprivate func renderCallback(inRefCon:UnsafeMutableRawPointer,
                    ioActionFlags:UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                    inTimeStamp:UnsafePointer<AudioTimeStamp>,
                    inBusNumber:UInt32,
                    inNumberFrames:UInt32,
                    ioData:UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
    let delegate = unsafeBitCast(inRefCon, to: AURenderCallbackDelegate.self)
    let result = delegate.performRender(ioActionFlags: ioActionFlags,
                                        inTimeStamp: inTimeStamp,
                                        inBusNumber: inBusNumber,
                                        inNumberFrames: inNumberFrames,
                                        ioData: ioData)
    return result
}

@objc protocol AURenderCallbackDelegate {
    func performRender(ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                       inTimeStamp: UnsafePointer<AudioTimeStamp>,
                       inBusNumber: UInt32,
                       inNumberFrames: UInt32,
                       ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus
}

//Low level audio playback implementation. Currently only supports non interleaved single channel data.
class AudioPlayer: AURenderCallbackDelegate {
    private var audioGraph: AUGraph?
    private var audioUnit: AudioUnit?

    #if os(iOS)
    private var audioDataBuffer: [UInt16] = []
    #elseif os(OSX)
    private var audioDataBuffer: [Float32] = []
    #endif
    private var mutex = pthread_mutex_t()

    var isReadyForMoreMediaData = true

    init() {
        pthread_mutex_init(&mutex, nil)
        initAudio()
    }

    deinit {
        if let audioGraph = audioGraph {
            DisposeAUGraph(audioGraph)
        }

        pthread_mutex_destroy(&mutex)
    }

    func start() -> Bool {
        guard let audioGraph = audioGraph else {
            Logger.error("Could not start audio graph")
            return false
        }

        return AUGraphStart(audioGraph) == noErr
    }

    func stop() -> Bool {
        guard let audioGraph = audioGraph else {
            Logger.error("Could not stop audio graph")
            return false
        }

        return AUGraphStop(audioGraph) == noErr
    }

    private func initAudio() {
        var outputNode: AUNode = 0
        var mixerNode: AUNode = 0

        NewAUGraph(&audioGraph)

        guard let audioGraph = audioGraph else {
            Logger.error("Could not create audio graph")
            return
        }

        var mixerComponentDescription = AudioComponentDescription(componentType: kAudioUnitType_Mixer, componentSubType: kAudioUnitSubType_SpatialMixer, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)

        #if os(iOS)
            var outputComponentDescription = AudioComponentDescription(componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_RemoteIO, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        #elseif os(OSX)
            var outputComponentDescription = AudioComponentDescription(componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_DefaultOutput, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        #endif

        AUGraphAddNode(audioGraph, &mixerComponentDescription, &mixerNode)
        AUGraphAddNode(audioGraph, &outputComponentDescription, &outputNode)

        AUGraphConnectNodeInput(audioGraph, mixerNode, 0, outputNode, 0)

        AUGraphOpen(audioGraph)

        AUGraphNodeInfo(audioGraph, mixerNode, nil, &audioUnit)

        guard let audioUnit = audioUnit else {
            Logger.error("Could not create audio unit")
            return
        }

        var elementCount: UInt32 = 1
        AudioUnitSetProperty(audioUnit, kAudioUnitProperty_ElementCount, kAudioUnitScope_Input, 0, &elementCount, UInt32(MemoryLayout<UInt32>.size))

        var callbackStruct: AURenderCallbackStruct = AURenderCallbackStruct(inputProc: renderCallback, inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())

        AUGraphSetNodeInputCallback(audioGraph, mixerNode, 0, &callbackStruct)

        #if os(iOS)
            var audioStreamBasicDescription = AudioStreamBasicDescription(mSampleRate: 44100.0, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagIsNonInterleaved, mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)

        #elseif os(OSX)
            var audioStreamBasicDescription = AudioStreamBasicDescription(mSampleRate: 44100.0, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved, mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
        #endif



        AudioUnitSetProperty(audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &audioStreamBasicDescription, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))

        AUGraphInitialize(audioGraph)

    }

    func performRender(ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>, inTimeStamp: UnsafePointer<AudioTimeStamp>, inBusNumber: UInt32, inNumberFrames: UInt32, ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {

        let mData = ioData?.pointee.mBuffers.mData

        let byteSize = Int(ioData!.pointee.mBuffers.mDataByteSize)
        memset(mData, 0, Int(ioData!.pointee.mBuffers.mDataByteSize))

        let frames = min(Int(inNumberFrames), audioDataBuffer.count)

        pthread_mutex_lock(&mutex)
        defer {
            pthread_mutex_unlock(&mutex)
        }

        if audioDataBuffer.count >= frames * 60 && frames != 0 {
            isReadyForMoreMediaData = false
        }

        if audioDataBuffer.count >= frames && frames != 0 {
            memcpy(mData, &audioDataBuffer, byteSize)
            audioDataBuffer.removeFirst(frames)
        } else {
            isReadyForMoreMediaData = true
        }

        return noErr
    }

    var firstSampleBuffer = true
    var audioBufferList = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 0, mDataByteSize: 0, mData: nil))
    func copyBuffer(sampleBuffer: CMSampleBuffer?) {
        guard let buffer = sampleBuffer else {
            return
        }

        if firstSampleBuffer == true {
            let formatDescription = CMSampleBufferGetFormatDescription(buffer)
            let audioDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription!)!.pointee

            var audioStreamBasicDescription: AudioStreamBasicDescription = AudioStreamBasicDescription()
            var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)

            AudioUnitGetProperty(audioUnit!, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &audioStreamBasicDescription, &size)

            audioStreamBasicDescription.mBitsPerChannel = audioDescription.mBitsPerChannel
            audioStreamBasicDescription.mBytesPerFrame = audioDescription.mBytesPerFrame
            audioStreamBasicDescription.mBytesPerPacket = audioDescription.mBytesPerPacket
            audioStreamBasicDescription.mChannelsPerFrame = audioDescription.mChannelsPerFrame
            //This line produces a crash on OSX. Need to investigate.
            //            audioStreamBasicDescription.mFormatFlags = audioDescription.mFormatFlags
            audioStreamBasicDescription.mFormatID = audioDescription.mFormatID
            audioStreamBasicDescription.mFramesPerPacket = audioDescription.mFramesPerPacket
            audioStreamBasicDescription.mReserved = audioDescription.mReserved
            audioStreamBasicDescription.mSampleRate = audioDescription.mSampleRate

            AudioUnitSetProperty(audioUnit!, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &audioStreamBasicDescription, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))

            AUGraphUpdate(audioGraph!, nil)

            firstSampleBuffer = false

            print(audioStreamBasicDescription)
        }

        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(buffer, nil, &audioBufferList, MemoryLayout<AudioBufferList>.size, nil, nil, kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, &blockBuffer)

        if status != noErr {
            print("Error with status code: \(status)")
            return
        }

        let audioBuffers = UnsafeBufferPointer<AudioBuffer>(start: &audioBufferList.mBuffers, count: Int(audioBufferList.mNumberBuffers))

        for audioBuffer in audioBuffers {
            // TODO: Use pointer logic instead of a typed array of values to remove system dependency logic
            #if os(iOS)
                let floatBuffer = audioBuffer.mData?.bindMemory(to: UInt16.self, capacity: Int(audioBuffer.mDataByteSize))
                let channelBufferData = UnsafeMutableBufferPointer<UInt16>(start: floatBuffer, count: Int(audioBuffer.mDataByteSize) / MemoryLayout<UInt16>.size)
            #elseif os(OSX)
                let floatBuffer = audioBuffer.mData?.bindMemory(to: Float32.self, capacity: Int(audioBuffer.mDataByteSize))
                let channelBufferData = UnsafeMutableBufferPointer<Float32>(start: floatBuffer, count: Int(audioBuffer.mDataByteSize) / MemoryLayout<Float32>.size)
            #endif
            
            pthread_mutex_lock(&mutex)
            defer {
                pthread_mutex_unlock(&mutex)
            }
            
            audioDataBuffer.append(contentsOf: channelBufferData)
        }
    }
}
