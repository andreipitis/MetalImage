//
//  Image.swift
//  Image
//
//  Created by Andrei-Sergiu Pițiș on 05/06/2017.
//  Copyright © 2017 Andrei-Sergiu Pițiș. All rights reserved.
//

import Foundation
import CoreMedia
import MetalKit

#if os(iOS)
    public typealias MIImage = UIImage
#elseif os(OSX)
    public typealias MIImage = NSImage

    extension NSImage {
        var cgImage: CGImage {
            var imageRect: CGRect = CGRect(x: 0.0, y: 0.0, width: self.size.width, height: self.size.height)
            let cgImage = self.cgImage(forProposedRect: &imageRect, context: nil, hints: nil)

            return cgImage!
        }
    }
#endif

public class Image: ImageSource {
    public var targets: [ImageConsumer] = []

    private(set) public var outputTexture: MTLTexture?

    private let context: MetalContext

    public init?(cgImage: CGImage?, context: MetalContext) {
        guard let cgImage = cgImage else {
            outputTexture = nil
            return nil
        }

        self.context = context

        let textureLoader = MTKTextureLoader(device: context.device)

        let options: [MTKTextureLoader.Option: Any] = [
            .textureStorageMode:   MTLStorageMode.private.rawValue as NSNumber,
            .textureUsage:         MTLTextureUsage.shaderRead.rawValue as NSNumber,
            .SRGB:                 false as NSNumber
        ]

        do {
            outputTexture = try textureLoader.newTexture(cgImage: cgImage, options: options)
        } catch {
            Logger.error(error)
            return nil
        }
    }

    public convenience init?(fileName: String, context: MetalContext) {
        #if os(OSX)
            let fileName = NSImage.Name(rawValue: fileName)
        #endif

        if let image = MIImage(named: fileName) {
            self.init(cgImage: image.cgImage, context: context)
        } else {
            return nil
        }
    }

    public func process() {
        for var target in targets {
            let commandBuffer = context.newCommandBuffer()
            target.inputTexture = outputTexture
            target.newFrameReady(at: kCMTimeZero, at: 0, using: commandBuffer)
        }
    }
}
