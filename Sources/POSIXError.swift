//
//  POSIXError.swift
//  SwiftySockets
//
//  Created by Michael Ferenduros on 08/08/2016.
//  Copyright © 2016 Mike Ferenduros. All rights reserved.
//

import Foundation


///Wrapper to make a non-`Error`s throwable
public struct ResultError<E> : Error {
    public let value: E
    init(_ value: E) { self.value = value }
}


///Minimal success/failure enum.
///Mostly useful as an alternative to throw (eg. when returning results via completion-handler)
public enum Result<R,E> {

    case result(R), error(E)

    /// - Returns `result`
    /// - Throws `error` in case of `.error`
    public func unwrap() throws -> R {
        switch self {
            case .result(let r): return r
            case .error(let e): throw (e as? Error) ?? ResultError(e)
        }
    }

    public var result: R? {
        switch self {
            case .result(let r): return r
            case .error: return nil
        }
    }

    public var error: E? {
        switch self {
            case .result: return nil
            case .error(let e): return e
        }
    }
}



public struct POSIXError : LocalizedError, Hashable, CustomDebugStringConvertible {

    public let code: Int32

    public var errorDescription: String? {
        return String(cString: strerror(code))
    }

    public var debugDescription: String {
        return "POSIXError(\(code)): \(errorDescription!)"
    }

    public init(_ code: Int32) {
        self.code = code
    }

    public var hashValue: Int { return code.hashValue }

    public static func ==(lhs: POSIXError, rhs: POSIXError) -> Bool {
        return lhs.code == rhs.code
    }

    public static func ~=(lhs: POSIXError, rhs: Error) -> Bool {
        return lhs == (rhs as? POSIXError)
    }
}
