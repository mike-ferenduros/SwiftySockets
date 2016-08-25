//
//  Socket6+properties.swift
//  SwiftySockets
//
//  Created by Michael Ferenduros on 25/08/2016.
//  Copyright © 2016 Mike Ferenduros. All rights reserved.
//

import Foundation


extension Socket6 {

    ///The socket's locally bound address, or zeroes if not applicable
    public var sockname: sockaddr_in6 {
        var address = sockaddr_in6()
        _ = address.withMutableSockaddr { getsockname(fd, $0, $1) }
        return address
    }

    ///The socket's connected address, or nil if the socket is not connected or an error occurs
    public var peername: sockaddr_in6? {
        var address = sockaddr_in6()
        let result = address.withMutableSockaddr { getpeername(fd, $0, $1) }
        return result == 0 ? address : nil
    }


    ///Returns and clears the current error (hence a function not a property)
    func getError() -> POSIXError? {
        guard let e = try? getsockopt(SOL_SOCKET, SO_ERROR, Int32.self) else { return nil }
        return e < 0 ? POSIXError(e) : nil
    }


    private func getboolopt(_ level: Int32, _ option: Int32) throws -> Bool {
        let value = try getsockopt(level, option, Int32.self)
        return value != 0
    }
    private func setboolopt(_ level: Int32, _ option: Int32, _ value: Bool) throws {
        try setsockopt(level, option, value ? Int32(1) : Int32(0))
    }

    var reuseAddress: Bool {
        get { return (try? getboolopt(SOL_SOCKET, SO_REUSEADDR)) ?? false }
        set { try? setboolopt(SOL_SOCKET, SO_REUSEADDR, newValue) }
    }
    var keepAlive: Bool {
        get { return (try? getboolopt(SOL_SOCKET, SO_KEEPALIVE)) ?? false }
        set { try? setboolopt(SOL_SOCKET, SO_KEEPALIVE, newValue) }
    }
    var broadcast: Bool {
        get { return (try? getboolopt(SOL_SOCKET, SO_BROADCAST)) ?? false }
        set { try? setboolopt(SOL_SOCKET, SO_BROADCAST, newValue) }
    }
    var noDelay: Bool {
        get { return (try? getboolopt(Int32(IPPROTO_TCP), TCP_NODELAY)) ?? false }
        set { try? setboolopt(Int32(IPPROTO_TCP), TCP_NODELAY, newValue) }
    }
}
