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

    public init(cgImage: CGImage?) {

        guard let cgImage = cgImage else {
            outputTexture = nil
            return
        }
        let textureLoader = MTKTextureLoader(device: MetalDevice.sharedInstance.device)

        let options: [MTKTextureLoader.Option: Any] = [
            .textureStorageMode:   MTLStorageMode.private,
            .textureUsage:         MTLTextureUsage.shaderRead,
            .SRGB:                 0
        ]

        outputTexture = try? textureLoader.newTexture(cgImage: cgImage, options: options)
    }

    public convenience init?(fileName: String) {
        #if os(iOS)
            if let image = UIImage(named: fileName) {
                self.init(cgImage: image.cgImage)
            } else {
                return nil
            }
        #elseif os(OSX)
            if let image = NSImage(named: NSImage.Name(rawValue: fileName)) {
                var imageRect: CGRect = CGRect(x: 0.0, y: 0.0, width: image.size.width, height: image.size.height)
                let cgImage = image.cgImage(forProposedRect: &imageRect, context: nil, hints: nil)
                self.init(cgImage: cgImage)
            } else {
                return nil
            }
        #endif
    }

    public func process() {
        for var target in targets {
            let commandBuffer = MetalDevice.sharedInstance.newCommandBuffer()

            target.inputTexture = outputTexture
            target.newFrameReady(at: kCMTimeZero, at: 0, using: commandBuffer)
        }
    }
}
