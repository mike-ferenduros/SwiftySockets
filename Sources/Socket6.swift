//
//  Socket6.swift
//  SwiftySockets
//
//  Created by Michael Ferenduros on 04/08/2016.
//  Copyright © 2016 Mike Ferenduros. All rights reserved.
//

import Foundation


private let sock_close = close
private let sock_shutdown = shutdown
private let sock_setsockopt = setsockopt
private let sock_getsockopt = getsockopt
private let sock_bind = bind
private let sock_accept = accept
private let sock_connect = connect
private let sock_listen = listen
private let sock_send = send
private let sock_sendto = sendto
private let sock_recv = recv
private let sock_recvfrom = recvfrom


/**
    Wrapper for socket descriptor, providing a slightly friendlier interface to the socket API
    Lifetime management is NOT handled
*/
public struct Socket6 : CustomDebugStringConvertible {

    public var debugDescription: String {
        return "fd \(fd): \(sockname) -> \(peername?.debugDescription ?? "unconnected")"
    }

    private func check(_ result: Int) throws { try check(Int32(result)) }
    private func check(_ result: Int32) throws {
        guard result >= 0 else {
            throw POSIXError(errno)
        }
    }


    ///The socket descriptor
    public let fd: Int32


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

    ///Initialise with an existing descriptor
    public init(fd: Int32) {
        self.fd = fd
    }

    ///Initialise with the desired type (usually SOCK_STREAM or SOCK_DGRAM)
    public init(type: Int32 = SOCK_STREAM) {
        self.init(fd: socket(AF_INET6, type, 0))
    }

    public func close() throws {
        let result = sock_close(fd)
        try check(result)
    }

    public enum ShutdownOptions: Int32 { case read = 0, write = 1, readwrite = 2 }
    public func shutdown(_ how: ShutdownOptions) throws {
        let result = sock_shutdown(fd, how.rawValue)
        try check(result)
    }

    public func setsockopt<T>(_ level: Int32, _ option: Int32, _ value: T) throws {
        var value = value
        let result = sock_setsockopt(fd, level, option, &value, socklen_t(sizeofValue(value)))
        try check(result)
    }

    public func getsockopt<T>(_ level: Int32, _ option: Int32, _ value: inout T) throws {
        var len = socklen_t(sizeof(T.self))
        let result = sock_getsockopt(fd, level, option, &value, &len)
        try check(result)
    }

    public func bind(to address: sockaddr_in6) throws {
        try? setsockopt(IPPROTO_IPV6, IPV6_V6ONLY, Int32(0))
        let result = address.withSockaddr { sock_bind(fd, $0, $1) }
        try check(result)
    }

    public func connect(to address: sockaddr_in6) throws {
        let result = address.withSockaddr { sock_connect(fd, $0, $1) }
        try check(result)
    }

    public func listen(backlog: Int = 16) throws {
        let result = sock_listen(fd, Int32(backlog))
        try check(result)
    }

    public func accept() throws -> Socket6 {
        var address = sockaddr_in6()
        let result = address.withMutableSockaddr { sock_accept(fd, $0, $1) }
        try check(result)
        return Socket6(fd: result)
    }


    public func send(buffer: UnsafePointer<Void>, length: Int, flags: Int32 = 0) throws -> Int {
        let result = sock_send(fd, buffer, length, flags)
        try check(result)
        return Int(result)
    }

    public func send(buffer: Data, flags: Int32 = 0) throws -> Int {
        let result = buffer.withUnsafeBytes { sock_send(fd, $0, buffer.count, flags) }
        try check(result)
        return Int(result)
    }

    public func send(buffer: UnsafePointer<Void>, length: Int, to address: sockaddr_in6, flags: Int32 = 0) throws -> Int {
        let result = address.withSockaddr { sock_sendto(fd, buffer, length, flags, $0, $1) }
        try check(result)
        return Int(result)
    }

    public func send(buffer: Data, to address: sockaddr_in6, flags: Int32 = 0) throws -> Int {
        return try buffer.withUnsafeBytes { try send(buffer: $0, length: buffer.count, to: address, flags: flags) }
    }

    public func recv(buffer: UnsafeMutablePointer<Void>, length: Int, flags: Int32 = 0) throws -> Int {
        let result = sock_recv(fd, buffer, length, flags)
        try check(result)
        return Int(result)
    }

    public func recv(length: Int, flags: Int32 = 0) throws -> Data {
        var buffer = Data(count: length)
        let result = buffer.withUnsafeMutableBytes { sock_recv(fd, $0, length, flags) }
        try check(result)
        return result == buffer.count ? buffer : buffer.subdata(in: 0..<result)
    }

    public func recvfrom(buffer: UnsafeMutablePointer<Void>, length: Int, flags: Int32 = 0) throws -> (Int,sockaddr_in6) {
        var addr = sockaddr_in6()
        let result = addr.withMutableSockaddr { sock_recvfrom(fd, buffer, length, flags, $0, $1) }
        try check(result)
        return (result, addr)
    }

    public func recvfrom(length: Int, flags: Int32 = 0) throws -> (Data,sockaddr_in6) {
        var buffer = Data(count: length)
        var address = sockaddr_in6()
        let result = buffer.withUnsafeMutableBytes { bytes in
            return address.withMutableSockaddr { addr, addrlen in
                return sock_recvfrom(fd, bytes, length, flags, addr, addrlen)
            }
        }
        try check(result)
        let outbuffer = result == buffer.count ? buffer : buffer.subdata(in: 0..<result)
        return (outbuffer, address)
    }
}
