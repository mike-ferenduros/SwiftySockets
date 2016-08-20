//
//  POSIXError.swift
//  SwiftySockets
//
//  Created by Michael Ferenduros on 08/08/2016.
//  Copyright © 2016 Mike Ferenduros. All rights reserved.
//

import Foundation


public struct POSIXError : LocalizedError, Equatable, CustomDebugStringConvertible {

    public let code: POSIXErrorCode

    public var errorDescription: String? {
        return String(cString: strerror(code.rawValue))
    }

    public var debugDescription: String {
        return "POSIXError(\(code.rawValue)): \(errorDescription!)"
    }

    public init(_ code: POSIXErrorCode) {
        self.code = code
    }

    public init(_ code: Int32) {
        self.code = POSIXErrorCode(rawValue:code)!
    }

    public static func ==(lhs: POSIXError, rhs: POSIXError) -> Bool {
        return lhs.code == rhs.code
    }

    public static func ~=(lhs: POSIXError, rhs: Error) -> Bool {
        return lhs == (rhs as? POSIXError)
    }
}
