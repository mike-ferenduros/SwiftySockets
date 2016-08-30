//
//  ListenSocket.swift
//  vrtest
//
//  Created by Michael Ferenduros on 27/08/2016.
//  Copyright © 2016 Mike Ferenduros. All rights reserved.
//

import Foundation


public class ListenSocket : DispatchSocket, DispatchSocketDelegate {

    override public var debugDescription: String {
        return "ListenSocket(\(socket))"
    }

    public struct Options : OptionSet {
        public init(rawValue: Int) { self.rawValue = rawValue }
        public let rawValue: Int
        
        ///SO_REUSEADDR: allow local address reuse
        public static let reuseAddress = Options(rawValue: 1<<0)

        ///IPV6_V6ONLY: only bind INET6 at wildcard bind
        public static let ip6Only      = Options(rawValue: 1<<1)
    }

    private let handler: (Socket6)->()

    public required init(address: sockaddr_in6, options: Options = [], handler: @escaping (Socket6)->()) throws {
        var s = try Socket6(type: .stream)
        s.reuseAddress = options.contains(.reuseAddress)
        s.ip6Only = options.contains(.ip6Only)
        try s.bind(to: address)
        self.handler = handler
        super.init(socket: s)
        self.delegate = self
        try socket.listen()
        self.notifyReadable = true
    }

    public convenience init(port: UInt16, options: Options = [], handler: @escaping (Socket6)->()) throws {
        try self.init(address: sockaddr_in6.any(port: port), options: options, handler: handler)
    }

    public convenience init(options: Options = [], handler: @escaping (Socket6)->()) throws {
        try self.init(address: sockaddr_in6.any(), options: options, handler: handler)
    }

    public func dispatchSocketIsReadable(_socket: DispatchSocket, count: Int) {
        if isOpen, let newsock = try? socket.accept() {
            handler(newsock)
        }
    }

    public func dispatchSocketIsWritable(_socket: DispatchSocket) { /* don't care */ }
    public func dispatchSocketDisconnected(_socket: DispatchSocket) { /* don't care */ }
}
