//
//  MetalImageLog.swift
//  MetalImage
//
//  Created by Andrei-Sergiu Pițiș on 29/06/2017.
//  Copyright © 2017 Andrei-Sergiu Pițiș. All rights reserved.
//

import Foundation

class Log {
    enum LogLevel: Int {
        case debug = 0
        case info = 1
        case warning = 2
        case error = 3
    }

    #if DEBUG
    static var level: LogLevel = .debug
    #endif

    class func debug(_ input: Any, file: StaticString = #file, function: StaticString = #function, line: Int = #line) {
        #if DEBUG
            guard self.level.rawValue >= LogLevel.debug.rawValue else {
                return
            }

            print("\u{001B}[0;34m\(Date())\n\(file):\n\(function)() Line \(line)\n\(input)\n\n")
        #endif
    }

    class func info(_ input: Any, file: StaticString = #file, function: StaticString = #function, line: Int = #line) {
        #if DEBUG
            guard self.level.rawValue >= LogLevel.info.rawValue else {
                return
            }

            print("\n\u{001B}[0;32m\(Date())\n\(file):\n\(function)() Line \(line)\n\(input)\n\n")
        #endif
    }

    class func warning(_ input: Any, file: StaticString = #file, function: StaticString = #function, line: Int = #line) {
        #if DEBUG
            guard self.level.rawValue >= LogLevel.warning.rawValue else {
                return
            }

            print("\n\u{001B}[0;33m\(Date())\n\(file):\n\(function)() Line \(line)\n\(input)\n\n")
        #endif
    }

    class func error(_ input: Any, file: StaticString = #file, function: StaticString = #function, line: Int = #line) {
        #if DEBUG
            guard self.level.rawValue >= LogLevel.error.rawValue else {
                return
            }

            print("\n\u{001B}[0;31m\(Date())\n\(file):\n\(function)() Line \(line)\n\(input)\n\n")
        #endif
    }
}
