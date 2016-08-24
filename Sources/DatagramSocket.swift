//
//  DatagramSocket.swift
//  SwiftySockets
//
//  Created by Michael Ferenduros on 03/08/2016.
//  Copyright © 2016 Mike Ferenduros. All rights reserved.
//

import Foundation
import Dispatch



public protocol DatagramSocketDelegate: class {
    func datagramSocket(_ socket: DatagramSocket, didReceive data: Data, from sender: sockaddr_in6)
}



/**
    Buffered, async UDP.
*/
public class DatagramSocket : CustomDebugStringConvertible {

    public var maxReadSize = 1500

    public weak var delegate: DatagramSocketDelegate?
    public let socket: Socket6
    private let readSource: DispatchSourceRead

    private(set) public var isOpen = true

    public var debugDescription: String {
        return "DatagramSocket \(socket.debugDescription)"
    }

    private init(socket: Socket6, delegate: DatagramSocketDelegate? = nil) {
        self.socket = socket
        self.delegate = delegate
        readSource = DispatchSource.makeReadSource(fileDescriptor: socket.fd, queue: DispatchQueue.main)
        readSource.setEventHandler { [weak self] in self?.readDatagrams() }
        readSource.resume()
    }

    public convenience init(boundTo address: sockaddr_in6, delegate: DatagramSocketDelegate? = nil) throws {
        self.init(socket: Socket6(type: .datagram), delegate: delegate)
        try self.socket.bind(to: address)
    }

    public convenience init(boundTo port: UInt16, delegate: DatagramSocketDelegate? = nil) throws {
        self.init(socket: Socket6(type: .datagram), delegate: delegate)
        try self.socket.bind(to: sockaddr_in6.any(port: port))
    }

    public convenience init(connectedTo address: sockaddr_in6, delegate: DatagramSocketDelegate? = nil) throws {
        self.init(socket: Socket6(type: .datagram), delegate: delegate)
        try self.socket.connect(to: address)
    }

    public func close() {
        if isOpen {
            readSource.cancel()
            try? socket.close()
            isOpen = false
        }
    }

    deinit {
        close()
    }



    private func readDatagrams() {
        guard isOpen else { return }

        while let (data,sender) = try? socket.recvfrom(length: self.maxReadSize, flags: MSG_DONTWAIT) {
            self.delegate?.datagramSocket(self, didReceive: data, from: sender)
        }
    }



    public func send(data: Data, to addr: sockaddr_in6?) {
        guard isOpen else { return }
        if let addr = addr {
            _ = try? socket.send(buffer: data, to: addr, flags: MSG_DONTWAIT)
        } else {
            _ = try? socket.send(buffer: data, flags: MSG_DONTWAIT)
        }
    }
}
