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

    ///The socket file-descriptor
    public let fd: Int32

    ///Initialize with an existing socket file-descriptor
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
        ///Provides raw network protocol access.
        case raw
        ///Provides sequenced, reliable, two-way, connection-based byte streams.  An out-of-band data transmission mechanism may be supported.
        case stream
        ///Supports datagrams (connectionless, unreliable messages of a fixed maximum length).
        case datagram
        ///Provides a reliable datagram layer that does not guarantee ordering.
        case reliableDatagram
        ///Provides a sequenced, reliable, two-way connection-based data transmission path for datagrams of fixed maximum length; a consumer is required to read an entire packet with each input system call.
        case seqPacket

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

    /**
    Creates an endpoint for IPv6 communication.

    - Parameter type: Specifies the communication semantics

    - Throws: POSIXError
        - `EACCES`: Permission to create a socket of the specified type and/or protocol is denied.
        - `EAFNOSUPPORT`: The implementation does not support the IPv6 address family.
        - `EINVAL`: Protocol family not available.
        - `EMFILE`: The per-process limit on the number of open file descriptors has been reached.
        - `ENFILE`: The system-wide limit on the total number of open files has been reached.
        - `ENOBUFS` or `ENOMEM`: Insufficient memory is available.  The socket cannot be created until sufficient resources are freed.
        - `EPROTONOSUPPORT`: The protocol type or the specified protocol is not supported within this domain.
    */
    public init(type: SocketType = .stream) throws {
        let result = socket(AF_INET6, type.rawValue, 0)
        guard result >= 0 else { throw POSIXError(errno) }
        self.init(fd: result)
    }

    /**
    Close the socket's file descriptor.
    
    - Throws: POSIXError
        - `EBADF`: `fd` isn't a valid open file descriptor.
        - `EINTR`: The call was interrupted by a signal.
        - `EIO`: An I/O error occurred.
    */
    public func close() throws {
        let result = sock_close(fd)
        try check(result)
    }

    public enum ShutdownOptions : RawRepresentable {
        ///Further receptions will be disallowed
        case read
        ///Further transmissions will be disallowed
        case write
        ///Further receptions and transmissions will be disallowed
        case readwrite
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
    /**
    Causes all or part of a full-duplex connection on the socket to be shut down.

    - Parameter how: Specifies whether transmission, reception or both are disallowed.
    
    - Throws: POSIXError
        - `EBADF`: `fd` is not a valid file descriptor
        - `ENOTCONN`: The socket is not connected
        - `ENOTSOCK`: `fd` does not refer to a socket.
    */
    public func shutdown(_ how: ShutdownOptions) throws {
        let result = sock_shutdown(fd, how.rawValue)
        try check(result)
    }
    
    public enum SocketOptionLevel : RawRepresentable {
        case socket, tcp, udp, ip, ipv6
        public init?(rawValue: Int32) {
            switch rawValue {
                case SOL_SOCKET:            self = .socket
                case Int32(IPPROTO_TCP):    self = .tcp
                case Int32(IPPROTO_UDP):    self = .udp
                case Int32(IPPROTO_IP):     self = .ip
                case Int32(IPPROTO_IPV6):   self = .ipv6
                default: return nil
            }
        }
        public var rawValue: Int32 {
            switch self {
                case .socket:   return SOL_SOCKET
                case .tcp:      return Int32(IPPROTO_TCP)
                case .udp:      return Int32(IPPROTO_UDP)
                case .ip:       return Int32(IPPROTO_IP)
                case .ipv6:     return Int32(IPPROTO_IPV6)
            }
        }
    }

    /**
    Set options for the socket.

    Options may exist at multiple protocol levels; they are always present at the uppermost socket level.

    - Parameter level: The level at which the option resides. To set options at the sockets API level, specify `.socket`.

    - Parameter option: Passed uninterpreted to the appropriate protocol module for interpretation.

    - Parameter value: Passed uninterpreted to the appropriate protocol module for interpretation.
    Most socket-level options utilize an `Int32` argument for `value`. The argument should be nonzero to enable a boolean option, or zero if the option is to be disabled.

    - Throws: POSIXError
        - `EBADF`: `fd` is not a valid file descriptor.
        - `EINVAL` Invalid value, or value is of invalid size for the specified option.
        - `ENOPROTOOPT`: The option is unknown at the level indicated.
        - `ENOTSOCK`: `fd` does not refer to a socket.    
    */
    public func setsockopt<T>(_ level: SocketOptionLevel, _ option: Int32, _ value: T) throws {
        var value = value
        let result = sock_setsockopt(fd, level.rawValue, option, &value, socklen_t(MemoryLayout<T>.size))
        try check(result)
    }

    /**
    Get options for the socket.
    
    Options may exist at multiple protocol levels; they are always present at the uppermost socket level.

    - Parameter level: The level at which the option resides. To set options at the sockets API level, specify `.socket`.
    
    - Parameter option: Passed uninterpreted to the appropriate protocol module for interpretation.

    - Parameter type: The type of the value to retrieve. Most socket-level options expect an `Int32.self` argument for `type`.
    
    - Throws: POSIXError
        - `EBADF`: `fd` is not a valid file descriptor.
        - `EINVAL` Invalid value, or type is of invalid size for the specified option.
        - `ENOPROTOOPT`: The option is unknown at the level indicated.
        - `ENOTSOCK`: `fd` does not refer to a socket.

    - Returns: The retrieved option value
    */
    public func getsockopt<T>(_ level: SocketOptionLevel, _ option: Int32, _ type: T.Type) throws -> T {
        //There must be a better way to make a T :(
        var len = socklen_t(MemoryLayout<T>.size)
        let buf = Data(count: MemoryLayout<T>.size)
        var value: T = buf.withUnsafeBytes { $0.pointee }
        let result = sock_getsockopt(fd, level.rawValue, option, &value, &len)
        try check(result)
        return value
    }

    /**
    When a socket is created, it has no address assigned to it.
    bind() assigns the address specified by `address` to the socket.
    Traditionally, this operation is called “assigning a name to a socket”.

    It is normally necessary to assign a local address using bind() before a .stream type socket may receive connections.

    - Parameter address: The address to assign to the socket

    - Throws: POSIXError
        - `EACCES` The address is protected, and the user is not the superuser.
        - `EADDRINUSE`: The given address is already in use.
        - `EADDRINUSE`: The port number was specified as zero in the socket address structure, but, upon attempting to bind to an ephemeral port, it was determined that all port numbers in the ephemeral port range are currently in use.
        - `EBADF`: `fd` is not a valid file descriptor.
        - `EINVAL`: The socket is already bound to an address.
        - `EINVAL`: `address` is not a valid address.
        - `ENOTSOCK`: `fd` does not refer to a socket.
    */
    public func bind(to address: sockaddr_in6) throws {
        let result = address.withSockaddr { sock_bind(fd, $0, $1) }
        try check(result)
    }

    /**
    Connects the socket to the address specified by `address`.

    If the socket sockfd is of type `.datagram`, then `address` is the address to which datagrams are sent by default, and the only address from which datagrams are received.
    
    If the socket is of type `.stream` or `.seqPacket`, this call attempts to make a connection to the socket that is bound to the address specified by `address`.

    Generally, connection-based protocol sockets may successfully `connect()` only once; connectionless protocol sockets may use `connect()` multiple times to change their association.

    - Parameter address: The address to connect to

    - Throws: POSIXError
        - `EACCES`, `EPERM`: The user tried to connect to a broadcast address without having the socket broadcast flag enabled or the connection request failed because of a local firewall rule.
        - `EADDRINUSE`: Local address is already in use.
        - `EADDRNOTAVAIL`: The socket had not previously been bound to an address and, upon attempting to bind it to an ephemeral port, it was determined that all port numbers in the ephemeral port range are currently in use.
        - `EAGAIN`: Insufficient entries in the routing cache.
        - `EALREADY`: The socket is nonblocking and a previous connection attempt has not yet been completed.
        - `EBADF`: `fd` is not a valid open file descriptor.
        - `ECONNREFUSED`: No-one listening on the remote address.
        - `EINPROGRESS`: The socket is nonblocking and the connection cannot be completed immediately.
        - `EINTR`: The system call was interrupted by a signal that was caught
        - `EISCONN`: The socket is already connected.
        - `ENETUNREACH`: Network is unreachable.
        - `ENOTSOCK`: `fd` does not refer to a socket.
        - `ETIMEDOUT`: Timeout while attempting connection. The server may be too busy to accept new connections. Note that the timeout may be very long when syncookies are enabled on the server.
    */
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

    /** 
    Marks the socket referred to as a passive socket, that is, as a socket that will be used to accept incoming connection requests using accept.

    The socket must be of type .stream or .seqPacket

    - Parameter backlog: defines the maximum length to which the queue of pending connections may grow. If a connection request arrives when the queue is full, the client may receive an error with an indication of ECONNREFUSED or, if the underlying protocol supports retransmission, the request may be ignored so that a later reattempt at connection succeeds.
    
    - Throws: POSIXError
        - `EADDRINUSE`: Another socket is already listening on the same port.
        - `EBADF`: `fd` not a valid file descriptor.
        - `ENOTSOCK`: `fd` does not refer to a socket.
        - `EOPNOTSUPP`: The socket is not of a type that supports the `listen` operation
    */
    public func listen(backlog: Int = 16) throws {
        let result = sock_listen(fd, Int32(backlog))
        try check(result)
    }

    /**
    Used with connection-based socket types (`.stream`, `.seqPacket`).
    It extracts the first connection request on the queue of pending connections for the listening socket, creates and returns a new connected socket.
    The newly created socket is not in the listening state.  The original socket is unaffected by this call.

    The socket should have been bound to a local address with `bind()`, and be listening for connections after a `listen()`.

    If no pending connections are present on the queue, and the socket is not marked as nonblocking, `accept()` blocks the caller until a connection is present.
    If the socket is marked nonblocking and no pending connections are present on the queue, `accept()` fails with the error EAGAIN or EWOULDBLOCK.

    In order to be notified of incoming connections on a socket, you can use DispatchSocket. A dispatchSocketIsReadable delegate event will be delivered when a new connection is attempted and you may then call `accept()` to get a socket for that connection.
    
    - Returns: A new connected socket
    
    - Throws: POSIXError
        - `EAGAIN` or `EWOULDBLOCK`: The socket is marked nonblocking and no connections are present to be accepted.
        - `EBADF`: `fd` is not an open file descriptor.
        - `ECONNABORTED`: A connection has been aborted.
        - `EINTR`: The system call was interrupted by a signal that was caught before a valid connection arrived.
        - `EINVAL`: Socket is not listening for connections
        - `EMFILE`: The per-process limit on the number of open file descriptors has been reached.
        - `ENFILE`: The system-wide limit on the total number of open files has been reached.
        - `ENOBUFS`, `ENOMEM`: Not enough free memory.  This often means that the memory allocation is limited by the socket buffer limits, not by the system memory.
        - `ENOTSOCK`: `fd` does not refer to a socket.
        - `EOPNOTSUPP`: The socket is not of type .stream
        - `EPROTO`: Protocol error.
        - `EPERM`: Firewall rules forbid connection.
    */
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

    /**
    Transmit a message to another socket.

   `send()` may be used only when the socket is in a connected state (so that the intended recipient is known). 

    If the message is too long to pass atomically through the underlying protocol, the `POSIXError` `EMSGSIZE` is thrown, and the message is not transmitted.

    No indication of failure to deliver is implicit in a send(). Locally detected errors are indicated by an exception.

    When the message does not fit into the send buffer of the socket, send() normally blocks, unless the socket has been placed in nonblocking I/O mode.

    In nonblocking mode it would fail with the `POSIXError` exception `EAGAIN` or `EWOULDBLOCK` in this case.

    The `DispatchSocket` class may be used to determine when it is possible to send more data.
    
    - Parameter buffer: A pointer to the message data to send
    
    - Parameter length: The length of the message in bytes
    
     - Parameter flags
        - `.oob`:  Sends out-of-band data on sockets that support this notion (e.g., of type `.stream`); the underlying protocol must also support out-of-band data.
        - `.dontRoute`: Don't use a gateway to send out the packet, send to hosts only on directly connected networks.  This is usually used only by diagnostic or routing programs.  This is defined only for protocol families that route; packet sockets don't.
        - `.eor`: Terminates a record (when this notion is supported, as for sockets of type `.seqPacket`).
        - `.dontWait`: Enables nonblocking operation; if the operation would block, `POSIXError` `EAGAIN` or `EWOULDBLOCK` is thrown.

    - Returns: The number of bytes sent

    - Throws: POSIXError
        - `EACCES`: (For UDP sockets) An attempt was made to send to a network/broadcast address as though it was a unicast address.
        - `EAGAIN` or `EWOULDBLOCK`: The socket is marked nonblocking and the requested operation would block.
        - `EBADF`: `fd` is not a valid open file descriptor.
        - `ECONNRESET`:  Connection reset by peer.
        - `EDESTADDRREQ`: The socket is not connection-mode, and no peer address is set.
        - `EINTR`: A signal occurred before any data was transmitted
        - `EINVAL`: Invalid argument passed.
        - `EMSGSIZE`: The socket type requires that message be sent atomically, and the size of the message to be sent made this impossible.
        - `ENOBUFS`: The output queue for a network interface was full.  This generally indicates that the interface has stopped sending, but may be caused by transient congestion.
        - `ENOMEM`: No memory available.
        - `ENOTCONN` The socket is not connected.
        - `ENOTSOCK`: `fd` does not refer to a socket.
        - `EOPNOTSUPP`: One of the specified flags is inappropriate for the socket type.
        - `EPIPE`: The local end has been shut down on a connection oriented socket.
    */
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
        public static let waitAll      = RecvFlags(rawValue: Int32(MSG_WAITALL))
        public static let dontWait     = RecvFlags(rawValue: Int32(MSG_DONTWAIT))
    }

    /**
    Receive messages from a socket.
    `recv()` may be used to receive data on both connectionless and connection-oriented sockets.  

    If a message is too long to fit in the supplied buffer, excess bytes may be discarded depending on the type of socket the message is received from.

    If no messages are available at the socket, `recv()` waits for a message to arrive, unless the socket is nonblocking, in which case the `POSIXError` `EAGAIN` or `EWOULDBLOCK` is thrown.
    
    `recv` normally return any data available, up to the requested amount, rather than waiting for receipt of the full amount requested.

    An application can use `DispatchSocket` to determine when more data arrives on a socket.

    - Parameter buffer: A pointer to memory to receive the message.

    - Parameter length: The maximum bytecount to receive. `buffer` must point to at least this many bytes of writable memory.

    - Parameter flags
        - `.oob`: This option requests receipt of out-of-band data that would not be received in the normal data stream.  Some protocols place expedited data at the head of the normal data queue, and thus this flag cannot be used with such protocols.
        - `.peek`:  This option causes the receive operation to return data from the beginning of the receive queue without removing that data from the queue.  Thus, a subsequent `recv()` call will return the same data.
        - `.waitAll`: This option requests that the operation block until the full request is satisfied.  However, the call may still return less data than requested if a signal is caught, an error or disconnect occurs, or the next data to be received is of a different type than that returned.  This option has no effect for datagram sockets.
        - `.dontWait`: Enables nonblocking operation; if the operation would block, `POSIXError` `EAGAIN` or `EWOULDBLOCK` is thrown.

    - Returns:
        The number of bytes received.

        When a stream socket peer has performed an orderly shutdown, the return value will be 0.

        Datagram sockets permit zero-length datagrams. When such a datagram is received, the return value is 0.

       The value 0 may also be returned from a stream socket parameter `length` was 0.

    - Throws: POSIXError
        - `EAGAIN` or `EWOULDBLOCK`: The socket is marked nonblocking and the receive operation would block, or a receive timeout had been set and the timeout expired before data was received.
        - `EBADF`: `fd` is an invalid file descriptor.
        - `ECONNREFUSED`:  A remote host refused to allow the network connection (typically because it is not running the requested service).
        - `EFAULT`: The receive buffer pointer points outside the process's address space.
        - `EINTR`: The receive was interrupted by delivery of a signal before any data were available.
        - `EINVAL`: Invalid argument passed.
        - `ENOTCONN`: The socket is associated with a connection-oriented protocol and has not been connected.
        - `ENOTSOCK`: `fd` does not refer to a socket.
    */
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
