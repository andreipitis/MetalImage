//
//  SepiaFilter.swift
//  MetalImage
//
//  Created by Andrei-Sergiu Pițiș on 30/03/2018.
//  Copyright © 2018 Andrei-Sergiu Pițiș. All rights reserved.
//

import Foundation
import Metal.MTLComputeCommandEncoder

public class SepiaFilter: BaseComputeFilter {
    private override init(computeShader: String, context: MetalContext) {
        super.init(computeShader: computeShader, context: context)
    }

    public convenience init(context: MetalContext) {
        self.init(computeShader: "sepiaCompute", context: context)
    }

    public override func configure(computeEncoder: MTLComputeCommandEncoder) {

    }
}
