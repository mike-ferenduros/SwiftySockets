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

#if os(Linux)
private func socktype(_ t: __socket_type) -> Int32 { return Int32(t.rawValue) }
#else
private func socktype(_ t: Int32) -> Int32 { return t }
#endif


/**
    Wrapper for socket descriptor, providing a slightly friendlier interface to the socket API
    Lifetime management is NOT handled
*/
public struct Socket6 : Hashable, RawRepresentable, CustomDebugStringConvertible {

    public var debugDescription: String {
        return "fd \(fd): \(sockname?.debugDescription ?? "unbound") -> \(peername?.debugDescription ?? "unconnected")"
    }

    public var hashValue: Int { return rawValue.hashValue }
    public static func ==(lhs: Socket6, rhs: Socket6) -> Bool { return lhs.rawValue == rhs.rawValue }

    public let fd: Int32
    public init(fd: Int32) { self.fd = fd }

    public var rawValue: Int32 { return fd }
    public init(rawValue: Int32) { self.init(fd: rawValue) }

    
    internal func check(_ result: Int) throws { try check(Int32(result)) }
    internal func check(_ result: Int32) throws {
        guard result >= 0 else {
            throw POSIXError(errno)
        }
    }


    public enum SocketType : RawRepresentable {

        case raw, stream, datagram, reliableDatagram, seqPacket
        public init?(rawValue: Int32) {
            switch rawValue {
                case socktype(SOCK_RAW):       self = .raw
                case socktype(SOCK_STREAM):    self = .stream
                case socktype(SOCK_DGRAM):     self = .datagram
                case socktype(SOCK_RDM):       self = .reliableDatagram
                case socktype(SOCK_SEQPACKET): self = .seqPacket
                default: return nil
            }
        }
        public var rawValue: Int32 {
            switch self {
                case .raw:              return socktype(SOCK_RAW)
                case .stream:           return socktype(SOCK_STREAM)
                case .datagram:         return socktype(SOCK_DGRAM)
                case .reliableDatagram: return socktype(SOCK_RDM)
                case .seqPacket:        return socktype(SOCK_SEQPACKET)
            }
        }
    }
    public init(type: SocketType = .stream) {
        self.init(fd: socket(AF_INET6, type.rawValue, 0))
    }

    public func close() throws {
        let result = sock_close(fd)
        try check(result)
    }

    public enum ShutdownOptions : RawRepresentable {
        case read, write, readwrite
        public init?(rawValue: Int32) {
            switch rawValue {
                case Int32(SHUT_RD):    self = .read
                case Int32(SHUT_WR):    self = .write
                case Int32(SHUT_RDWR):  self = .readwrite
                default: return nil
            }
        }
        public var rawValue: Int32 {
            switch self {
                case .read:         return Int32(SHUT_RD)
                case .write:        return Int32(SHUT_WR)
                case .readwrite:    return Int32(SHUT_RDWR)
            }
        }
    }
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
        //There must be a better way to make a T :(
        var len = socklen_t(MemoryLayout<T>.size)
        let buf = Data(count: MemoryLayout<T>.size)
        var value: T = buf.withUnsafeBytes { $0.pointee }
        let result = sock_getsockopt(fd, level, option, &value, &len)
        try check(result)
        return value
    }

    public func bind(to address: sockaddr_in6) throws {
        let result = address.withSockaddr { sock_bind(fd, $0, $1) }
        try check(result)
    }

    public func connect(to address: sockaddr_in6) throws {
        let result = address.withSockaddr { sock_connect(fd, $0, $1) }
        try check(result)
    }

    ///Look up and connect to hostname:port, returning the address used
    public func connect(to hostname: String, port: UInt16) throws -> sockaddr_in6 {
        let addresses = try sockaddr_in6.getaddrinfo(hostname: hostname, port: port)
        var errors: [Error] = []
        for address in addresses {
            do {
                try connect(to: address)
                return address
            } catch let e {
                errors.append(e)
            }
        }
        throw errors.first ?? POSIXError(EAI_SYSTEM)        //Shouldn't happen.
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

    ///Receive all available data (which may be 0-byte datagram)
    public func recv(flags: RecvFlags = []) throws -> Data {
        return try recv(length: self.availableBytes, flags: flags)
    }

    ///Receive all available data (which may be 0-byte datagram)
    public func recvfrom(flags: RecvFlags = []) throws -> (Data,sockaddr_in6) {
        return try recvfrom(length: self.availableBytes, flags: flags)
    }
}
