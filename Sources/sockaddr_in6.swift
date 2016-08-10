//
//  sockaddr_in6.swift
//  SwiftySockets
//
//  Created by Michael Ferenduros on 03/08/2016.
//  Copyright © 2016 Mike Ferenduros. All rights reserved.
//

import Foundation


//When strict typing meets a crufty API...

extension in6_addr : CustomStringConvertible {
    public var description: String {
        var str = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        var mself = self
        inet_ntop(AF_INET6, &mself, &str, socklen_t(str.count))
        return String(cString: str)
    }

    var bytes: [UInt8] {
        get {
            var result = [UInt8](repeating: 0, count: 16)
            var mself = self
            memcpy(&result, &mself, 16)
            return result
        }
        set {
            guard newValue.count == 16 else { fatalError() }
            memcpy(&self, newValue, 16)
        }
    }
}


///Extension to reduce the pain of working with sockaddr_in6
extension sockaddr_in6 : CustomDebugStringConvertible {

    public var debugDescription: String {
        return "\(sin6_addr) / \(self.port))"
    }

    ///Port number, reflecting sin6_port
    public var port: UInt16 {
        get { return sin6_port.bigEndian }
        set { sin6_port = newValue.bigEndian }
    }

    /** 
        IP address, reflecting sin6_addr.
        Always reads as array of 16 bytes
        May be written as array of either 4 or 16 bytes
        4-byte addresses are converted to IPv6 representation
    */
    public var ip: [UInt8] {
        get {
            return self.sin6_addr.bytes
        }

        set {
            switch newValue.count {
                case 4:     self.sin6_addr.bytes = [0,0,0,0,0,0,0,0,0,0,0xFF,0xFF] + newValue
                case 16:    self.sin6_addr.bytes = newValue
                default:    fatalError()
            }
        }
    }

    public var valid: Bool {
        return (Int32(sin6_family) == AF_INET6) && (Int(sin6_len) == sizeof(sockaddr_in6.self))
    }

    ///Wildcard address, optionally with port
    public static func any(port: UInt16 = 0) -> sockaddr_in6 {
        return sockaddr_in6(ip: [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], port: port)
    }

    ///Loopback address, optionally with port
    public static func loopback(port: UInt16 = 0) -> sockaddr_in6 {
        return sockaddr_in6(ip: [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1], port: port)
    }

    ///Initialise with zero (=wildcard) address.
    public init() {
        self.init(
            sin6_len: UInt8(sizeof(sockaddr_in6.self)),
            sin6_family: sa_family_t(AF_INET6),
            sin6_port: 0,
            sin6_flowinfo: 0,
            sin6_addr: in6_addr(),
            sin6_scope_id: 0
        )
    }

    /**
        Initialise with either 4- or 16-byte address, plus port number
        4-byte addresses are converted to IPv6 representation
    */
    public init(ip: [UInt8], port: UInt16) {
        self.init()
        self.ip = ip
        self.port = port
    }

    /**
        Initialise from IPv4 sockaddr structure, converting address to IPv6 representation
    */
    public init(sa: sockaddr_in) {
        let ip4 = sa.sin_addr.s_addr.bigEndian
        let ip = (0..<4).map { UInt8((ip4 >> ($0*8)) & 0xFF) }
        self.init(ip: ip, port: sa.sin_port.bigEndian)
    }
    

    /**
        Initialise from a data containing either an IPv4 or IPv6 sockaddr
    */
    public init?(data: Data) {
        let family = data.withUnsafeBytes { (sa: UnsafePointer<sockaddr>) -> Int32 in Int32(sa.pointee.sa_family) }

        switch family {
            case AF_INET:
                guard data.count >= sizeof(sockaddr_in.self) else { return nil }
                let sa4 = data.withUnsafeBytes { (sa: UnsafePointer<sockaddr_in>) -> sockaddr_in in sa.pointee }
                self.init(sa: sa4)

            case AF_INET6:
                guard data.count >= sizeof(sockaddr_in6.self) else { return nil }
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
                guard Int(ai.ai_addrlen) == sizeof(sockaddr_in6.self) else { return nil }
                guard let sa6 = UnsafePointer<sockaddr_in6>(ai.ai_addr) else { return nil }
                self.init(ip: sa6.pointee.ip, port: sa6.pointee.port)

            case AF_INET:
                guard Int(ai.ai_addrlen) == sizeof(sockaddr_in.self) else { return nil }
                guard let sa4 = UnsafePointer<sockaddr_in>(ai.ai_addr) else { return nil }
                self.init(sa: sa4.pointee)
            
            default:
                return nil
        }
    }


    /**
        Invoke 'block' with a pointer to self and size, and returning the block's return-value

        Useful for passing self to socket functions that require an input sockaddr pointer
    */
    public func withSockaddr<T>(_ block: @noescape (UnsafePointer<sockaddr>,socklen_t)->T) -> T {
        let thisIsRidiculous: @noescape(UnsafePointer<sockaddr_in6>)->T = { ptr in
            return block(UnsafePointer<sockaddr>(ptr), socklen_t(sizeof(sockaddr_in6.self)))
        }
        var sa = self
        return thisIsRidiculous(&sa)
    }

    /**
        Invoke 'block' with a mutable pointer to self and size, and returning the block's return-value

        Useful for passing self to socket functions that require an output sockaddr pointer

        On block-completion, modified length parameter is ignored
    */
    public mutating func withMutableSockaddr<T>(_ block: @noescape(UnsafeMutablePointer<sockaddr>,UnsafeMutablePointer<socklen_t>)->T) -> T {
        var maxLen = socklen_t(sizeof(sockaddr_in6.self))
        let thisIsRidiculous: @noescape(UnsafeMutablePointer<sockaddr_in6>)->T = { ptr in
            return block(UnsafeMutablePointer<sockaddr>(ptr), &maxLen)
        }
        return thisIsRidiculous(&self)
    }
}


private let sock_getaddrinfo = getaddrinfo

extension sockaddr_in6 {

    /**
        Invoke getaddrinfo to lookup IPv6 addresses for a hostname, on a global queue.
        Invokes completion on main queue with results, or [] if an error occurred
    */
    public static func getaddrinfo(hostname: String, port: UInt16, completion: ([sockaddr_in6], POSIXError?)->()) {
        DispatchQueue.global().async {
            let cstr = hostname.cString(using: .utf8)
            let port = "\(port)".cString(using: .utf8)
            var addresses: UnsafeMutablePointer<addrinfo>?
            var hint = addrinfo(ai_flags: 0, ai_family: AF_INET6, ai_socktype: 0, ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
            var results: [sockaddr_in6] = []

            guard sock_getaddrinfo(cstr, port, &hint, &addresses) == 0  else {
                let error = POSIXError(errno)
                return DispatchQueue.main.async { completion([], error) }
            }

            var curr = addresses
            while let info = curr?.pointee {
                if let sa = sockaddr_in6(ai: info) {
                    results.append(sa)
                }
                curr = info.ai_next
            }

            freeaddrinfo(addresses)

            DispatchQueue.main.async { completion(results, nil) }
        }
    }
}
