//
//  PassthroughFilter.swift
//  MetalImage
//
//  Created by Andrei-Sergiu Pițiș on 29/03/2018.
//  Copyright © 2018 Andrei-Sergiu Pițiș. All rights reserved.
//

import Foundation
import Metal.MTLRenderCommandEncoder

public class PassthroughFilter: BaseRenderFilter {
    override init(vertexShader: String, fragmentShader: String, context: MetalContext) {
        super.init(vertexShader: vertexShader, fragmentShader: fragmentShader, context: context)
    }

    public convenience init(context: MetalContext) {
        self.init(vertexShader: "passthroughVertex", fragmentShader: "passthroughFragment", context: context)
    }

    public override func configure(renderEncoder: MTLRenderCommandEncoder) {
        
    }
}
