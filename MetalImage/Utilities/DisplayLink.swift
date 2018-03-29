//
//  DisplayLink.swift
//  MetalImage
//
//  Created by Andrei-Sergiu Pițiș on 29/03/2018.
//  Copyright © 2018 Andrei-Sergiu Pițiș. All rights reserved.
//

import Foundation
import CoreVideo

#if os(iOS)
    typealias MIDisplayLink = CADisplayLink
    typealias MITimestamp = CFTimeInterval
#elseif os(OSX)
    typealias MIDisplayLink = CVDisplayLink
    typealias MITimestamp = CVTimeStamp
#endif

class DisplayLink {
    private var displayLink: MIDisplayLink?

    private var timestamp: MITimestamp!

    private var callback: ((MIDisplayLink, MITimestamp) -> Void)

    init(callback: @escaping (MIDisplayLink, MITimestamp) -> Void) {
        self.callback = callback

        #if os(iOS)
            displayLink = CADisplayLink(target: self, selector: #selector(render))
            displayLink?.add(to: RunLoop.main, forMode: .defaultRunLoopMode)
            displayLink?.isPaused = true
        #elseif os(OSX)
            CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
            CVDisplayLinkSetOutputHandler(displayLink!) { [weak self] (displayLink, inNow, inOutputTime, flagsIn, flagsOut) -> CVReturn in
                self?.timestamp = inNow.pointee
                self?.run(displayLink: displayLink)
                return kCVReturnSuccess
            }
        #endif
    }

    deinit {
        Log.debug("Deinit Display Link")
    }

    func start() {
        guard let displayLink = displayLink else {
            Log.debug("Display Link in nil.")
            return
        }
        #if os(iOS)
            displayLink.isPaused = false
        #elseif os(OSX)
            CVDisplayLinkStart(displayLink)
        #endif
    }

    func stop() {
        guard let displayLink = displayLink else {
            Log.debug("Display Link in nil.")
            return
        }

        #if os(iOS)
            displayLink.isPaused = true
        #elseif os(OSX)
            CVDisplayLinkStop(displayLink)
        #endif
    }

    func invalidate() {
        #if os(iOS)
            displayLink?.invalidate()
        #endif
    }

    func run(displayLink: MIDisplayLink) {
        #if os(iOS)
            let timestamp = displayLink.timestamp
        #elseif os(OSX)
            let timestamp = self.timestamp!
        #endif

        callback(displayLink, timestamp)
    }
}
