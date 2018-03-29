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
            Log(error)
        }
    }

    public convenience init?(fileName: String, context: MetalContext) {
        #if os(iOS)
            if let image = UIImage(named: fileName) {
                self.init(cgImage: image.cgImage, context: context)
            } else {
                return nil
            }
        #elseif os(OSX)
            if let image = NSImage(named: NSImage.Name(rawValue: fileName)) {
                var imageRect: CGRect = CGRect(x: 0.0, y: 0.0, width: image.size.width, height: image.size.height)
                let cgImage = image.cgImage(forProposedRect: &imageRect, context: nil, hints: nil)
                self.init(cgImage: cgImage, context: context)
            } else {
                return nil
            }
        #endif
    }

    public func process() {
        for var target in targets {
            let commandBuffer = context.newCommandBuffer()
            target.inputTexture = outputTexture
            target.newFrameReady(at: kCMTimeZero, at: 0, using: commandBuffer)
        }
    }
}
