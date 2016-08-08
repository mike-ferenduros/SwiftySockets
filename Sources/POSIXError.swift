//
//  POSIXError.swift
//  SwiftySockets
//
//  Created by Michael Ferenduros on 08/08/2016.
//  Copyright © 2016 Mike Ferenduros. All rights reserved.
//

import Foundation


struct POSIXError : Error, Equatable {

    static let domain = "net.mike-ferenduros.SwiftySockets.POSIXError"
    let _domain = POSIXError.domain
    let _code: Int

    var description: String {
        return String(cString: strerror(Int32(_code)))
    }
    
    var debugDescription: String {
        return "POSIXError(\(_code)): \(description)"
    }

    init(_ code: Int32) {
        self._code = Int(code)
    }

    static func ==(lhs: POSIXError, rhs: POSIXError) -> Bool {
        return lhs._code == rhs._code
    }

    static func ~=(lhs: POSIXError, rhs: Error) -> Bool {
        return lhs == (rhs as? POSIXError)
    }
}
