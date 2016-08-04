//
//  sockaddr_in6.swift
//  SwiftySockets
//
//  Created by Michael Ferenduros on 03/08/2016.
//  Copyright © 2016 Mike Ferenduros. All rights reserved.
//

import Foundation


//When strict typing meets a crufty API...


extension sockaddr_in6 {

    public var port: UInt16 {
        get { return sin6_port.bigEndian }
        set { sin6_port = newValue.bigEndian }
    }

    public var ip: [UInt8] {
        get {
            var src = sin6_addr.__u6_addr.__u6_addr8
            var result = [UInt8](repeatElement(0, count: 16))
            memcpy(&result, &src, 16)
            return result
        }

        set {
            var bytes = newValue
            if bytes.count == 4 {
                bytes = [0,0,0,0,0,0,0,0,0,0,0xFF,0xFF] + bytes
            } else if bytes.count != 16 {
                //A bit extreme maybe...
                fatalError()
            }
            memcpy(&sin6_addr.__u6_addr.__u6_addr8, bytes, 16)
        }
    }

    public var valid: Bool {
        return (Int32(sin6_family) == AF_INET6) && (Int(sin6_len) == sizeof(sockaddr_in6.self))
    }


    public static func any(port: UInt16 = 0) -> sockaddr_in6 {
        return sockaddr_in6(ip: [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], port: port)
    }

    public static func loopback(port: UInt16 = 0) -> sockaddr_in6 {
        return sockaddr_in6(ip: [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1], port: port)
    }


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

    //IP4 or IP6
    public init(ip: [UInt8], port: UInt16) {
        self.init()
        self.ip = ip
        self.port = port
    }

    public init(_ block: @noescape(UnsafeMutablePointer<sockaddr>,UnsafeMutablePointer<socklen_t>)->()) {
        self.init()
        self.withMutableSockaddr(block)
    }

    public init(sa: sockaddr_in) {
        let ip4 = sa.sin_addr.s_addr.bigEndian
        let ip = (0..<4).map { UInt8((ip4 >> ($0*8)) & 0xFF) }
        self.init(ip: ip, port: sa.sin_port.bigEndian)
    }

    //NB: sockaddr is actually too small to contain a complete sockaddr_in6. Hence this pass-by-pointer bullshit.
    public init?(sockaddr sa: UnsafePointer<sockaddr>) {
        if Int32(sa.pointee.sa_family) == AF_INET6 {
            guard Int(sa.pointee.sa_len) == sizeof(sockaddr_in6.self) else { return nil }
            self.init()
            memcpy(&self, sa, sizeof(sockaddr_in6.self))
        } else if Int32(sa.pointee.sa_family) == AF_INET {
            guard Int(sa.pointee.sa_len) == sizeof(sockaddr_in.self) else { return nil }
            var sa4 = sockaddr_in()
            memcpy(&sa4, sa, sizeof(sockaddr_in.self))
            self.init(sa: sa4)
        } else {
            return nil
        }
    }



    public func withSockaddr<T>(_ block: @noescape (UnsafePointer<sockaddr>,socklen_t)->T) -> T {
        let thisIsRidiculous: @noescape(UnsafePointer<sockaddr_in6>)->T = { ptr in
            return block(UnsafePointer<sockaddr>(ptr), socklen_t(sizeof(sockaddr_in6.self)))
        }
        var sa = self
        return thisIsRidiculous(&sa)
    }

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

    public static func getaddrinfo(hostname: String, port: UInt16, completion: ([sockaddr_in6])->()) {
        DispatchQueue.global().async {
            let cstr = hostname.cString(using: .utf8)
            let port = "\(port)".cString(using: .utf8)
            var addresses: UnsafeMutablePointer<addrinfo>?
            var hint = addrinfo(ai_flags: 0, ai_family: AF_INET6, ai_socktype: 0, ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
            var results: [sockaddr_in6] = []
            if sock_getaddrinfo(cstr, port, &hint, &addresses) == 0 {

                if let addresses = addresses { defer { freeaddrinfo(addresses) } }

                var curr = addresses
                while let info = curr?.pointee {
                    if let sa = sockaddr_in6(sockaddr: info.ai_addr) {
                        results.append(sa)
                    }
                    curr = info.ai_next
                }
            }
            DispatchQueue.main.async { completion(results) }
        }
    }
}
