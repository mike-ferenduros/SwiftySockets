//
//  DispatchSocket+listen.swift
//  vrtest
//
//  Created by Michael Ferenduros on 27/08/2016.
//  Copyright © 2016 Mike Ferenduros. All rights reserved.
//

import Foundation


public class ListenSocket : DispatchSocket, DispatchSocketReadableDelegate {

    override public var debugDescription: String {
        return "ListenSocket(\(socket.debugDescription))"
    }

    public struct ListenOptions : OptionSet {
        public init(rawValue: Int) { self.rawValue = rawValue }
        public let rawValue: Int

        ///SO_REUSEADDR: allow local address reuse
        public static let reuseAddress = ListenOptions(rawValue: 1<<0)

        ///IPV6_V6ONLY: only bind INET6 at wildcard bind
        public static let ip6Only      = ListenOptions(rawValue: 1<<1)
    }

    private var acceptHandler: ((Socket6)->())?

    public init(address: sockaddr_in6, options: ListenOptions = [], handler: @escaping (Socket6)->()) throws {
        var s = try Socket6(type: .stream)
        s.reuseAddress = options.contains(.reuseAddress)
        s.ip6Only = options.contains(.ip6Only)
        try s.bind(to: address)
        super.init(socket: s)
        self.acceptHandler = handler
        self.readableDelegate = self
        try socket.listen()
    }

    public func dispatchSocketReadable(_ socket: DispatchSocket, count: Int) {
        if isOpen, let sock = try? self.socket.accept() {
            acceptHandler?(sock)
        }
    }

    public convenience init(port: UInt16, options: ListenOptions = [], handler: @escaping (Socket6)->()) throws {
        try self.init(address: sockaddr_in6.any(port: port), options: options, handler: handler)
    }

    public convenience init(options: ListenOptions = [], handler: @escaping (Socket6)->()) throws {
        try self.init(address: sockaddr_in6.any(), options: options, handler: handler)
    }
}
