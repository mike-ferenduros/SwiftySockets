//
//  sockaddr_in6.swift
//  SwiftySockets
//
//  Created by Michael Ferenduros on 03/08/2016.
//  Copyright © 2016 Mike Ferenduros. All rights reserved.
//

import Foundation
import Dispatch


//When strict typing meets a crufty API...

extension in6_addr : Hashable, CustomStringConvertible {

    public var hashValue: Int { return bytes.reduce(5381) { ($0 << 5) &+ $0 &+ Int($1) } }
    
    public var description: String {
        var str = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        var mself = self
        inet_ntop(AF_INET6, &mself, &str, socklen_t(str.count))
        return String(cString: str)
    }

    public static func ==(lhs: in6_addr, rhs: in6_addr) -> Bool {
        return lhs.bytes == rhs.bytes
    }

    public static let any = in6_addr(bytes: [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0])
    public static let loopback = in6_addr(bytes: [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1])

    /**
        Initialise with either 4- or 16-byte address
        4-byte addresses are converted to IPv4-mapped IPv6 representation
    */
    public init(bytes: [UInt8]) {
        self.init()
        self.bytes = bytes
    }

    /**
        Initialise with IPv4 or IPv6 string, eg. "123.123.123.123" or "2001:db8:85a3::8a2e:370:7334"
    */
    public init?(_ string: String) {
        let cstr = Array(string.utf8CString)
        var addr6 = in6_addr()
        if inet_pton(AF_INET6, cstr, &addr6) == 1 {
            self.init(addr6)
        } else {
            var addr4 = in_addr()
            if inet_pton(AF_INET, cstr, &addr4) == 1 {
                self.init(addr4)
            } else {
                return nil
            }
        }
    }

    public init(_ addr: in6_addr) {
        self = addr
    }

    /**
        Initialise as IPv4-mapped IPv6 address
    */
    public init(_ in4: in_addr) {
        self.init()
        let ip4 = in4.s_addr.bigEndian
        self.bytes = (0..<4).map { UInt8((ip4 >> (24 - $0*8)) & 0xFF) }
    }

    /**
        Always reads as array of 16 bytes
        May be written as array of either 4 or 16 bytes
        4-byte addresses are converted to IPv4-mapped IPv6 addresses
    */
    public var bytes: [UInt8] {
        get {
            var result = [UInt8](repeating: 0, count: 16)
            var mself = self
            memcpy(&result, &mself, 16)
            return result
        }
        set {
            switch newValue.count {
                case 4:     memcpy(&self, [0,0,0,0,0,0,0,0,0,0,0xFF,0xFF] + newValue, 16)
                case 16:    memcpy(&self, newValue, 16)
                default:    fatalError()
            }
        }
    }
}


///Extension to reduce the pain of working with sockaddr_in6
extension sockaddr_in6 : Hashable, CustomDebugStringConvertible {

    public var debugDescription: String {
        return "\(sin6_addr) / \(self.port)"
    }

    public var hashValue: Int { return sin6_addr.hashValue ^ Int(sin6_port) ^ Int(sin6_flowinfo) ^ Int(sin6_scope_id) }

    public static func ==(lhs: sockaddr_in6, rhs: sockaddr_in6) -> Bool {
        return lhs.sin6_addr == rhs.sin6_addr && lhs.sin6_port == rhs.sin6_port && lhs.scope_id == rhs.scope_id && lhs.flowinfo == rhs.flowinfo
    }

    ///Port number, reflecting sin6_port
    public var port: UInt16 {
        get { return sin6_port.bigEndian }
        set { sin6_port = newValue.bigEndian }
    }

    public var flowinfo: UInt32 {
        get { return sin6_flowinfo.bigEndian }
        set { sin6_flowinfo = newValue.bigEndian }
    }

    public var scope_id: UInt32 {
        get { return sin6_scope_id.bigEndian }
        set { sin6_scope_id = newValue.bigEndian }
    }

    ///Wildcard address, optionally with port
    public static func any(port: UInt16 = 0) -> sockaddr_in6 {
        return sockaddr_in6(addr: in6_addr.any, port: port)
    }

    ///Loopback address, optionally with port
    public static func loopback(port: UInt16 = 0) -> sockaddr_in6 {
        return sockaddr_in6(addr: in6_addr.loopback, port: port)
    }

    ///Initialise with zero (=wildcard) address.
    public init() {
        #if os(Linux)
        self.init(
            sin6_family: sa_family_t(AF_INET6),
            sin6_port: 0,
            sin6_flowinfo: 0,
            sin6_addr: in6_addr.any,
            sin6_scope_id: 0
        )
        #else
        self.init(
            sin6_len: UInt8(MemoryLayout<sockaddr_in6>.size),
            sin6_family: sa_family_t(AF_INET6),
            sin6_port: 0,
            sin6_flowinfo: 0,
            sin6_addr: in6_addr.any,
            sin6_scope_id: 0
        )
        #endif
    }

    public init(addr: in6_addr, port: UInt16, flowinfo: UInt32 = 0, scope_id: UInt32 = 0) {
        self.init()
        self.sin6_addr = addr
        self.port = port
        self.flowinfo = flowinfo
        self.scope_id = scope_id
    }

    public init?(addr: String, port: UInt16, flowinfo: UInt32 = 0, scope_id: UInt32 = 0) {
        guard let a = in6_addr(addr) else { return nil }
        self.init(addr: a, port: port, flowinfo: flowinfo, scope_id: scope_id)
    }

    /**
        Initialise from IPv4 sockaddr structure, converting to IPv4-mapped IPv6
    */
    public init(sa: sockaddr_in) {
        let addr = in6_addr(sa.sin_addr)
        self.init(addr: addr, port: sa.sin_port.bigEndian)
    }


    /**
        Initialise from a data containing either an IPv4 or IPv6 sockaddr
    */
    public init?(data: Data) {
        let family = data.withUnsafeBytes { (sa: UnsafePointer<sockaddr>) -> Int32 in Int32(sa.pointee.sa_family) }

        switch family {
            case AF_INET:
                guard data.count >= MemoryLayout<sockaddr_in>.size else { return nil }
                let sa4 = data.withUnsafeBytes { (sa: UnsafePointer<sockaddr_in>) -> sockaddr_in in sa.pointee }
                self.init(sa: sa4)

            case AF_INET6:
                guard data.count >= MemoryLayout<sockaddr_in6>.size else { return nil }
                self.init()
                self = data.withUnsafeBytes { (sa: UnsafePointer<sockaddr_in6>) -> sockaddr_in6 in sa.pointee }
            
            default:
                return nil
        }
    }

    /**
        Initialise from addrinfo
        Can handle either sockaddr_in or sockaddr_in6 pointees; returns nil otherwise.
    */
    public init?(ai: addrinfo) {
        switch ai.ai_family {
            case AF_INET6:
                guard Int(ai.ai_addrlen) == MemoryLayout<sockaddr_in6>.size else { return nil }
                self.init()
                guard let sa = ai.ai_addr else { return nil }
                let sa6 = sa.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { return $0.pointee }
                self = sa6
                self.sin6_family = sa_family_t(AF_INET6)
                #if !os(Linux)
                self.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
                #endif

            case AF_INET:
                guard Int(ai.ai_addrlen) == MemoryLayout<sockaddr_in>.size else { return nil }
                guard let sa = ai.ai_addr else { return nil }
                let sa4 = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { return $0.pointee }
                self.init(sa: sa4)

            default:
                return nil
        }
    }


    /**
        Invoke 'block' with a pointer to self and size, and returning the block's return-value

        Useful for passing self to socket functions that require an input sockaddr pointer
    */
    public func withSockaddr<T>(_ block: (UnsafePointer<sockaddr>,socklen_t)->T) -> T {
        var mself = self
        return withUnsafePointer(to: &mself) { sa6 in
            sa6.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                block(sa, socklen_t(MemoryLayout<sockaddr_in6>.size))
            }
        }
    }

    /**
        Invoke 'block' with a mutable pointer to self and size, and returning the block's return-value

        Useful for passing self to socket functions that require an output sockaddr pointer

        On block-completion, modified length parameter is ignored
    */
    public mutating func withMutableSockaddr<T>(_ block: (UnsafeMutablePointer<sockaddr>,UnsafeMutablePointer<socklen_t>)->T) -> T {
        var maxLen = socklen_t(MemoryLayout<sockaddr_in6>.size)
        return withUnsafeMutablePointer(to: &self) { sa6 in
            sa6.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                block(sa, &maxLen)
            }
        }
    }
}


private let sock_getaddrinfo = getaddrinfo

extension sockaddr_in6 {

    /**
        Invoke getaddrinfo to lookup IPv6 addresses for a hostname.
    */
    public static func getaddrinfo(hostname: String, port: UInt16) throws -> [sockaddr_in6] {
        let cstr = hostname.cString(using: .utf8)
        let port = "\(port)".cString(using: .utf8)
        var addresses: UnsafeMutablePointer<addrinfo>?
        #if os(Linux)
        var hint = addrinfo(ai_flags: 0, ai_family: Int32(AF_INET6), ai_socktype: 0, ai_protocol: 0, ai_addrlen: 0, ai_addr: nil, ai_canonname: nil, ai_next: nil)
        #else
        var hint = addrinfo(ai_flags: 0, ai_family: Int32(AF_INET6), ai_socktype: 0, ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        #endif
        var results: [sockaddr_in6] = []

        guard sock_getaddrinfo(cstr, port, &hint, &addresses) == 0  else { throw POSIXError(errno) }

        var curr = addresses
        while let info = curr?.pointee {
            if let sa = sockaddr_in6(ai: info) {
                results.append(sa)
            }
            curr = info.ai_next
        }

        freeaddrinfo(addresses)
        return results
    }

    public static func getaddrinfo(hostname: String, port: UInt16, completion: @escaping (Result<[sockaddr_in6], Error>)->()) {
        DispatchQueue.global().async {
            do {
                let results = try getaddrinfo(hostname: hostname, port: port)
                DispatchQueue.main.async { completion(.success(results)) }
            } catch let e {
                DispatchQueue.main.async { completion(.failure(e)) }
            }
        }
    }
}
