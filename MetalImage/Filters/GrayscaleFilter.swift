//
//  GrayscaleFilter.swift
//  MetalImage
//
//  Created by Andrei-Sergiu Pițiș on 29/03/2018.
//  Copyright © 2018 Andrei-Sergiu Pițiș. All rights reserved.
//

import Foundation
import Metal.MTLComputeCommandEncoder

public class GrayscaleFilter: BaseComputeFilter {
    private override init(computeShader: String, context: MetalContext) {
        super.init(computeShader: computeShader, context: context)
    }

    public convenience init(context: MetalContext) {
        self.init(computeShader: "grayscaleCompute", context: context)
    }

    public override func configure(computeEncoder: MTLComputeCommandEncoder) {

    }
}
