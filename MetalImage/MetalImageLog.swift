//
//  MetalImageLog.swift
//  MetalImage
//
//  Created by Andrei-Sergiu Pițiș on 29/06/2017.
//  Copyright © 2017 Andrei-Sergiu Pițiș. All rights reserved.
//

import Foundation

func Log(_ input: Any, file: StaticString = #file, function: StaticString = #function, line: Int = #line) {
    #if DEBUG
        print("\n\(Date())\n\(file):\n\(function)() Line \(line)\n\(input)\n\n")
    #endif
}
