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

    public var type: SocketType {
        //This is a terrible punt
        guard let t = try? getsockopt(.socket, SO_TYPE, Int32.self), let result = SocketType(rawValue: t) else { return .raw }
        return result
    }

    ///SO_ERROR: Returns and clears the current error (hence a function not a property)
    public func getError() -> POSIXError? {
        guard let e = try? getsockopt(.socket, SO_ERROR, Int32.self) else { return nil }
        return e < 0 ? POSIXError(e) : nil
    }


    private func getboolopt(_ level: SocketOptionLevel, _ option: Int32) throws -> Bool {
        let value = try getsockopt(level, option, Int32.self)
        return value != 0
    }
    private func setboolopt(_ level: SocketOptionLevel, _ option: Int32, _ value: Bool) throws {
        try setsockopt(level, option, value ? Int32(1) : Int32(0))
    }

    ///SO_REUSEADDR: allow local address reuse
    public func setReuseAddress(_ newValue: Bool) {
        try? setboolopt(.socket, SO_REUSEADDR, newValue)
    }
    ///SO_REUSEADDR: allow local address reuse
    public var reuseAddress: Bool {
        get { return (try? getboolopt(.socket, SO_REUSEADDR)) ?? false }
        set { setReuseAddress(newValue) }
    }

    ///SO_KEEPALIVE: keep connections alive
    public func setKeepAlive(_ newValue: Bool) {
        try? setboolopt(.socket, SO_KEEPALIVE, newValue)
    }
    ///SO_KEEPALIVE: keep connections alive
    public var keepAlive: Bool {
        get { return (try? getboolopt(.socket, SO_KEEPALIVE)) ?? false }
        set { setKeepAlive(newValue) }
    }

    ///SO_BROADCAST: permit sending of broadcast msgs
    public func setBroadcast(_ newValue: Bool) {
        try? setboolopt(.socket, SO_BROADCAST, newValue)
    }
    ///SO_BROADCAST: permit sending of broadcast msgs
    public var broadcast: Bool {
        get { return (try? getboolopt(.socket, SO_BROADCAST)) ?? false }
        set { setBroadcast(newValue) }
    }

    ///SO_DONTROUTE: just use interface addresses
    public func setDontRoute(_ newValue: Bool) {
        try? setboolopt(.socket, SO_DONTROUTE, newValue)
    }
    ///SO_DONTROUTE: just use interface addresses
    public var dontRoute: Bool {
        get { return (try? getboolopt(.socket, SO_DONTROUTE)) ?? false }
        set { setDontRoute(newValue) }
    }

    ///TCP_NODELAY: don't delay send to coalesce packets
    public func setNoDelay(_ newValue: Bool) {
        try? setboolopt(.tcp, TCP_NODELAY, newValue)
    }
    ///TCP_NODELAY: don't delay send to coalesce packets
    public var noDelay: Bool {
        get { return (try? getboolopt(.tcp, TCP_NODELAY)) ?? false }
        set { setNoDelay(newValue) }
    }

    ///IPV6_V6ONLY: only bind INET6 at wildcard bind
    public func setIP6Only(_ newValue: Bool) {
        try? setboolopt(.ipv6, Int32(IPV6_V6ONLY), newValue)
    }
    ///IPV6_V6ONLY: only bind INET6 at wildcard bind
    public var ip6Only: Bool {
        get { return (try? getboolopt(.ipv6, Int32(IPV6_V6ONLY))) ?? false }
        set { setIP6Only(newValue) }
    }

    ///SO_ACCEPTCONN: socket has had listen()
    public var isListening: Bool {
        return (try? getboolopt(.socket, SO_ACCEPTCONN)) ?? false
    }

    ///SO_NREAD / FIONREAD: Bytes available to read in the next recv call (ie. datagram size if UDP). 
    public var availableBytes: Int {
        #if os(Linux)
        var size: CInt = 0
        let result = ioctl(fd, UInt(FIONREAD), &size)
        try! check(result)
        return Int(size)
        #else
        let size = try! getsockopt(.socket, SO_NREAD, UInt32.self)
        return Int(size)
        #endif
    }

    #if !os(Linux)
    public enum NetServiceType: RawRepresentable {
        case bestEffort, background, signaling, interactiveVideo, interactiveVoice, responsiveAV, streamingAV, management, responsiveData
        public init?(rawValue: Int32) {
            switch rawValue {
                case NET_SERVICE_TYPE_BE:   self = .bestEffort
                case NET_SERVICE_TYPE_BK:   self = .background
                case NET_SERVICE_TYPE_SIG:  self = .signaling
                case NET_SERVICE_TYPE_VI:   self = .interactiveVideo
                case NET_SERVICE_TYPE_VO:   self = .interactiveVoice
                case NET_SERVICE_TYPE_RV:   self = .responsiveAV
                case NET_SERVICE_TYPE_AV:   self = .streamingAV
                case NET_SERVICE_TYPE_OAM:  self = .management
                case NET_SERVICE_TYPE_RD:   self = .responsiveData
                default: return nil
            }
        }
        public var rawValue: Int32 {
            switch self {
                case .bestEffort:       return NET_SERVICE_TYPE_BE
                case .background:       return NET_SERVICE_TYPE_BK
                case .signaling:        return NET_SERVICE_TYPE_SIG
                case .interactiveVideo: return NET_SERVICE_TYPE_VI
                case .interactiveVoice: return NET_SERVICE_TYPE_VO
                case .responsiveAV:     return NET_SERVICE_TYPE_RV
                case .streamingAV:      return NET_SERVICE_TYPE_AV
                case .management:       return NET_SERVICE_TYPE_OAM
                case .responsiveData:   return NET_SERVICE_TYPE_RD
            }
        }
    }

    ///SO_NET_SERVICE_TYPE: Network service type
    public func setNetServiceType(_ newValue: NetServiceType) {
        try? setsockopt(.socket, SO_NET_SERVICE_TYPE, newValue.rawValue)
    }
    ///SO_NET_SERVICE_TYPE: Network service type
    public var netServiceType: NetServiceType {
        get {
            guard let rawType = try? getsockopt(.socket, SO_NET_SERVICE_TYPE, Int32.self) else { return .bestEffort }
            return NetServiceType(rawValue: rawType) ?? .bestEffort
        }
        set { setNetServiceType(newValue) }
    }
    #endif
}
