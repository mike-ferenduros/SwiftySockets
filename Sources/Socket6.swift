//
//  Socket6.swift
//  SwiftySockets
//
//  Created by Michael Ferenduros on 04/08/2016.
//  Copyright © 2016 Mike Ferenduros. All rights reserved.
//

import Foundation
import Dispatch


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
public struct Socket6 : Hashable, CustomDebugStringConvertible {

    public var debugDescription: String {
        return "fd \(fd): \(sockname) -> \(peername?.debugDescription ?? "unconnected")"
    }

    public var hashValue: Int { return Int(fd) }
    public static func ==(lhs: Socket6, rhs: Socket6) -> Bool { return lhs.fd == rhs.fd }

    private func check(_ result: Int) throws { try check(Int32(result)) }
    private func check(_ result: Int32) throws {
        guard result >= 0 else {
            throw POSIXError(errno)
        }
    }


    ///The socket descriptor
    public let fd: Int32


    ///Initialise with an existing descriptor
    public init(fd: Int32) {
        self.fd = fd
    }

    ///Initialise with the desired type
    public enum SocketType { case raw, stream, datagram }
    public init(type: SocketType = .stream) {
        let stype = [.raw: SOCK_RAW, .stream: SOCK_STREAM, .datagram: SOCK_DGRAM][type]!
        #if os(Linux)
        self.init(fd: socket(AF_INET6, Int32(stype.rawValue), 0))
        #else
        self.init(fd: socket(AF_INET6, stype, 0))
        #endif
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
        let result = sock_setsockopt(fd, level, option, &value, socklen_t(MemoryLayout<T>.size))
        try check(result)
    }

    public func getsockopt<T>(_ level: Int32, _ option: Int32, _ type: T.Type) throws -> T {
        var len = socklen_t(MemoryLayout<T>.size)
        let buf = Data(count: MemoryLayout<T>.size)
        var value: T = buf.withUnsafeBytes { $0.pointee }
        let result = sock_getsockopt(fd, level, option, &value, &len)
        try check(result)
        return value
    }

    public func bind(to address: sockaddr_in6) throws {
        try? setsockopt(Int32(IPPROTO_IPV6), Int32(IPV6_V6ONLY), Int32(0))
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



    public struct SendFlags : OptionSet {
        public init(rawValue: Int32) { self.rawValue = rawValue }
        public let rawValue: Int32

        //Only the intersection of Linux & Mac flags for now
        public static let oob          = SendFlags(rawValue: Int32(MSG_OOB))
        public static let dontRoute    = SendFlags(rawValue: Int32(MSG_DONTROUTE))
        public static let eor          = SendFlags(rawValue: Int32(MSG_EOR))
        public static let dontWait     = SendFlags(rawValue: Int32(MSG_DONTWAIT))
    }

    public func send(buffer: UnsafeRawPointer, length: Int, flags: SendFlags = []) throws -> Int {
        let result = sock_send(fd, buffer, length, flags.rawValue)
        try check(result)
        return Int(result)
    }

    public func send(buffer: Data, flags: SendFlags = []) throws -> Int {
        let result = buffer.withUnsafeBytes { sock_send(fd, $0, buffer.count, flags.rawValue) }
        try check(result)
        return Int(result)
    }

    public func send(buffer: UnsafeRawPointer, length: Int, to address: sockaddr_in6, flags: SendFlags = []) throws -> Int {
        let result = address.withSockaddr { sock_sendto(fd, buffer, length, flags.rawValue, $0, $1) }
        try check(result)
        return Int(result)
    }

    public func send(buffer: Data, to address: sockaddr_in6, flags: SendFlags = []) throws -> Int {
        return try buffer.withUnsafeBytes { try send(buffer: $0, length: buffer.count, to: address, flags: flags) }
    }



    public struct RecvFlags : OptionSet {
        public init(rawValue: Int32) { self.rawValue = rawValue }
        public let rawValue: Int32

        //Only the intersection of Linux & Mac flags for now
        public static let oob          = RecvFlags(rawValue: Int32(MSG_OOB))
        public static let peek         = RecvFlags(rawValue: Int32(MSG_PEEK))
        public static let trunc        = RecvFlags(rawValue: Int32(MSG_TRUNC))
        public static let waitAll      = RecvFlags(rawValue: Int32(MSG_WAITALL))
        public static let dontWait     = RecvFlags(rawValue: Int32(MSG_DONTWAIT))
    }

    public func recv(buffer: UnsafeMutableRawPointer, length: Int, flags: RecvFlags = []) throws -> Int {
        let result = sock_recv(fd, buffer, length, flags.rawValue)
        try check(result)
        return Int(result)
    }

    public func recv(length: Int, flags: RecvFlags = []) throws -> Data {
        var buffer = Data(count: length)
        let result = buffer.withUnsafeMutableBytes { sock_recv(fd, $0, length, flags.rawValue) }
        try check(result)
        return result == buffer.count ? buffer : buffer.subdata(in: 0..<result)
    }

    public func recvfrom(buffer: UnsafeMutableRawPointer, length: Int, flags: RecvFlags = []) throws -> (Int,sockaddr_in6) {
        var addr = sockaddr_in6()
        let result = addr.withMutableSockaddr { sock_recvfrom(fd, buffer, length, flags.rawValue, $0, $1) }
        try check(result)
        return (result, addr)
    }

    public func recvfrom(length: Int, flags: RecvFlags = []) throws -> (Data,sockaddr_in6) {
        var buffer = Data(count: length)
        var address = sockaddr_in6()
        let result = buffer.withUnsafeMutableBytes { bytes in
            return address.withMutableSockaddr { addr, addrlen in
                return sock_recvfrom(fd, bytes, length, flags.rawValue, addr, addrlen)
            }
        }
        try check(result)
        let outbuffer = result == buffer.count ? buffer : buffer.subdata(in: 0..<result)
        return (outbuffer, address)
    }
}
