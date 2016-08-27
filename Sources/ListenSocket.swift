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
    
    private let handler: (Socket6)->()
    
    public required init(socket: Socket6, handler: @escaping (Socket6)->()) throws {
        self.handler = handler
        super.init(socket: socket)
        self.delegate = self
        try socket.listen()
        self.notifyReadable = true
    }

    public convenience init(address: sockaddr_in6, reuseAddress: Bool = false, handler: @escaping (Socket6)->()) throws {
        var s = Socket6(type: .stream)
        if reuseAddress {
            s.reuseAddress = true
        }
        try s.bind(to: address)
        try self.init(socket: s, handler: handler)
    }

    public convenience init(port: UInt16 = 0, reuseAddress: Bool = false, handler: @escaping (Socket6)->()) throws {
        try self.init(address: sockaddr_in6.any(port: port), reuseAddress: reuseAddress, handler: handler)
    }

    public func dispatchSocketIsReadable(_socket: DispatchSocket, count: Int) {
        if isOpen, let newsock = try? socket.accept() {
            handler(newsock)
        }
    }

    public func dispatchSocketIsWritable(_socket: DispatchSocket) { /* don't care */ }
    public func dispatchSocketDisconnected(_socket: DispatchSocket) { /* don't care */ }
}
