//
//  Static.swift
//  MetalImage
//
//  Created by Andrei-Sergiu Pițiș on 30/01/2018.
//  Copyright © 2018 Andrei-Sergiu Pițiș. All rights reserved.
//

import Foundation

public struct Static {
    static let vertexData: [Float] = [-1.0, 1.0,
                                      1.0, 1.0,
                                      1.0, -1.0,
                                      -1.0, -1.0]

    static let indexData: [UInt16] = [0, 1, 2, 2, 3, 0]

    enum TextureRotation {
        case none
        case left
        case right
        case flipVertical
        case flipHorizontal

        func rotation() -> [Float] {
            switch self {
            case .none:
                return [
                    0.0, 0.0,
                    1.0, 0.0,
                    1.0, 1.0,
                    0.0, 1.0
                ]
            case .left:
                return [
                    1.0, 0.0,
                    1.0, 1.0,
                    0.0, 1.0,
                    0.0, 0.0
                ]
            case .right:
                return [
                    0.0, 1.0,
                    0.0, 0.0,
                    1.0, 0.0,
                    1.0, 1.0,
                ]
            case .flipVertical:
                return [
                    0.0, 1.0,
                    1.0, 1.0,
                    1.0, 0.0,
                    0.0, 0.0
                ]
            case .flipHorizontal:
                return [
                    1.0, 0.0,
                    0.0, 0.0,
                    0.0, 1.0,
                    1.0, 1.0
                ]
            }
        }
    }
}
