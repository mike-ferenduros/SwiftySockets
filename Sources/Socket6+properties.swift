//
//  Socket6+properties.swift
//  SwiftySockets
//
//  Created by Michael Ferenduros on 25/08/2016.
//  Copyright © 2016 Mike Ferenduros. All rights reserved.
//

import Foundation


extension Socket6 {

    ///The socket's locally bound address, or nil if not bound/connected or an error occurs
    public var sockname: sockaddr_in6? {
        var address = sockaddr_in6()
        let result = address.withMutableSockaddr { getsockname(fd, $0, $1) }
        return result == 0 ? address : nil
    }

    ///The socket's connected address, or nil if the socket is not connected or an error occurs
    public var peername: sockaddr_in6? {
        var address = sockaddr_in6()
        let result = address.withMutableSockaddr { getpeername(fd, $0, $1) }
        return result == 0 ? address : nil
    }


    ///Returns and clears the current error (hence a function not a property)
    public func getError() -> POSIXError? {
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

    public func setReuseAddress(_ newValue: Bool) {
        try? setboolopt(SOL_SOCKET, SO_REUSEADDR, newValue)
    }
    public var reuseAddress: Bool {
        get { return (try? getboolopt(SOL_SOCKET, SO_REUSEADDR)) ?? false }
        set { setReuseAddress(newValue) }
    }

    public func setKeepAlive(_ newValue: Bool) {
        try? setboolopt(SOL_SOCKET, SO_KEEPALIVE, newValue)
    }
    public var keepAlive: Bool {
        get { return (try? getboolopt(SOL_SOCKET, SO_KEEPALIVE)) ?? false }
        set { setKeepAlive(newValue) }
    }

    public func setBroadcast(_ newValue: Bool) {
        try? setboolopt(SOL_SOCKET, SO_BROADCAST, newValue)
    }
    public var broadcast: Bool {
        get { return (try? getboolopt(SOL_SOCKET, SO_BROADCAST)) ?? false }
        set { setBroadcast(newValue) }
    }

    public func setDontRoute(_ newValue: Bool) {
        try? setboolopt(SOL_SOCKET, SO_DONTROUTE, newValue)
    }
    public var dontRoute: Bool {
        get { return (try? getboolopt(SOL_SOCKET, SO_DONTROUTE)) ?? false }
        set { setDontRoute(newValue) }
    }

    public func setNoDelay(_ newValue: Bool) {
        try? setboolopt(Int32(IPPROTO_TCP), TCP_NODELAY, newValue)
    }
    public var noDelay: Bool {
        get { return (try? getboolopt(Int32(IPPROTO_TCP), TCP_NODELAY)) ?? false }
        set { setNoDelay(newValue) }
    }

    public func setIP6Only(_ newValue: Bool) {
        try? setboolopt(Int32(IPPROTO_IPV6), Int32(IPV6_V6ONLY), newValue)
    }
    public var ip6Only: Bool {
        get { return (try? getboolopt(Int32(IPPROTO_IPV6), Int32(IPV6_V6ONLY))) ?? false }
        set { setIP6Only(newValue) }
    }

    public var isListening: Bool {
        get { return (try? getboolopt(SOL_SOCKET, SO_ACCEPTCONN)) ?? false }
    }

    #if !os(Linux)
    public enum NetServiceType: Int {
        case bestEffort=0, background, signaling, interactiveVideo, interactiveVoice, responsiveAV, streamingAV, management, responsiveData
        private static let rawServiceTypes = [NET_SERVICE_TYPE_BE, NET_SERVICE_TYPE_BK, NET_SERVICE_TYPE_SIG, NET_SERVICE_TYPE_VI, NET_SERVICE_TYPE_VO, NET_SERVICE_TYPE_RV, NET_SERVICE_TYPE_AV, NET_SERVICE_TYPE_OAM, NET_SERVICE_TYPE_RD]
        init?(rawServiceType: Int32) {
            guard let idx = NetServiceType.rawServiceTypes.index(of: rawServiceType) else { return nil }
            self.init(rawValue: idx)
        }
        var rawType: Int32 { return NetServiceType.rawServiceTypes[self.rawValue] }
    }

    public func setNetServiceType(_ newValue: NetServiceType) {
        try? setsockopt(SOL_SOCKET, SO_NET_SERVICE_TYPE, newValue.rawType)
    }
    public var netServiceType: NetServiceType {
        get {
            guard let rawType = try? getsockopt(SOL_SOCKET, SO_NET_SERVICE_TYPE, Int32.self) else { return .bestEffort }
            return NetServiceType(rawServiceType: rawType) ?? .bestEffort
        }
        set { setNetServiceType(newValue) }
    }
    #endif
}
