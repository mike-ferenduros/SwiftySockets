//
//  DatagramSocket.swift
//  SwiftySockets
//
//  Created by Michael Ferenduros on 03/08/2016.
//  Copyright © 2016 Mike Ferenduros. All rights reserved.
//

import Foundation



public protocol DatagramSocketDelegate: class {
    func datagramSocket(_ socket: DatagramSocket, didReceive data: Data, from sender: sockaddr_in6)
}



/**
    Buffered, async UDP.
*/
public class DatagramSocket {

    public var maxReadSize = 1500

    public weak var delegate: DatagramSocketDelegate?
    public let socket: Socket6

    private(set) var isOpen = true


    private let readSource: DispatchSourceRead
    private let writeSource: DispatchSourceWrite


    private init(socket: Socket6, delegate: DatagramSocketDelegate? = nil) {
        self.socket = Socket6(type: SOCK_DGRAM)

        readSource = DispatchSource.makeReadSource(fileDescriptor: socket.fd, queue: DispatchQueue.main)
        writeSource = DispatchSource.makeWriteSource(fileDescriptor: socket.fd, queue: DispatchQueue.main)
        readSource.setEventHandler { [weak self] in self?.readDatagrams() }
        writeSource.setEventHandler { [weak self] in self?.writeQueued() }
        readSource.activate()
        writeSource.activate()
    }

    public convenience init(boundTo address: sockaddr_in6, delegate: DatagramSocketDelegate? = nil) throws {
        self.init(socket: Socket6(type: SOCK_DGRAM), delegate: delegate)
        try self.socket.bind(to: address)
    }

    public convenience init(boundTo port: UInt16, delegate: DatagramSocketDelegate? = nil) throws {
        self.init(socket: Socket6(type: SOCK_DGRAM), delegate: delegate)
        try self.socket.bind(to: sockaddr_in6.any(port: port))
    }

    public convenience init(connectedTo address: sockaddr_in6, delegate: DatagramSocketDelegate? = nil) throws {
        self.init(socket: Socket6(type: SOCK_DGRAM), delegate: delegate)
        try self.socket.connect(to: address)
    }

    public func close() {
        readSource.cancel()
        writeSource.cancel()
        try? socket.close()
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



    private var sendQueue: [(data:Data,addr:sockaddr_in6?)] = []

    private func writeQueued() {
        guard isOpen else { return }
        while let item = sendQueue.first {

            do {
                if let addr = item.addr {
                    _ = try socket.send(buffer: item.data, to: addr, flags: MSG_DONTWAIT)
                } else {
                    _ = try socket.send(buffer: item.data, flags: MSG_DONTWAIT)
                }
            }
            catch POSIXError(EAGAIN) { return }
            catch POSIXError(EWOULDBLOCK) { return }
            catch {}

            _ = sendQueue.removeFirst()
        }
    }

    public func send(data: Data, to addr: sockaddr_in6?) {
        sendQueue.append((data: data, addr: addr))
        writeQueued()
    }
}
