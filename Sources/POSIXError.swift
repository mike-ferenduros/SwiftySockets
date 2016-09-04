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
public enum Result<V,E> {

    case success(V), failure(E)

    ///Returns `value`, else throws `error`. If `error` doesn't conform to `Error`, it's wrapped in `ResultError` before being thrown.
    public func unwrap() throws -> V {
        switch self {
            case .success(let value): return value
            case .failure(let error): throw (error as? Error) ?? ResultError(error)
        }
    }

    public var value: V? {
        switch self {
            case .success(let value): return value
            case .failure: return nil
        }
    }

    public var error: E? {
        switch self {
            case .success: return nil
            case .failure(let error): return error
        }
    }
}



public struct POSIXError : LocalizedError, Equatable, CustomDebugStringConvertible {

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

    public static func ==(lhs: POSIXError, rhs: POSIXError) -> Bool {
        return lhs.code == rhs.code
    }

    public static func ~=(lhs: POSIXError, rhs: Error) -> Bool {
        return lhs == (rhs as? POSIXError)
    }
}
