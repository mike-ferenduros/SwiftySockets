//
//  POSIXError.swift
//  SwiftySockets
//
//  Created by Michael Ferenduros on 08/08/2016.
//  Copyright © 2016 Mike Ferenduros. All rights reserved.
//

import Foundation


public struct POSIXError : Error, Equatable, CustomStringConvertible, CustomDebugStringConvertible {

    public static let domain = "net.mike-ferenduros.SwiftySockets.POSIXError"
    public let _domain = POSIXError.domain
    public let _code: Int

    public var description: String {
        return String(cString: strerror(Int32(_code)))
    }

    public var debugDescription: String {
        return "POSIXError(\(_code)): \(description)"
    }

    public init(_ code: Int32) {
        self._code = Int(code)
    }

    public static func ==(lhs: POSIXError, rhs: POSIXError) -> Bool {
        return lhs._code == rhs._code
    }

    public static func ~=(lhs: POSIXError, rhs: Error) -> Bool {
        return lhs == (rhs as? POSIXError)
    }
}
