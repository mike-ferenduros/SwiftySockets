//
//  StreamSocket.swift
//  SwiftySockets
//
//  Created by Michael Ferenduros on 03/08/2016.
//  Copyright © 2016 Mike Ferenduros. All rights reserved.
//

import Foundation
import Dispatch


public protocol StreamSocketDelegate {
    func streamSocketDidDisconnect(_ socket: StreamSocket)
}


/**
    Buffered, async TCP
*/
public class StreamSocket : Hashable, CustomDebugStringConvertible, DispatchSocketDelegate {

    private let dsock: DispatchSocket
    public var socket: Socket6 { return dsock.socket }
    public var isOpen: Bool { return dsock.isOpen }

    public var hashValue: Int { return dsock.hashValue }
    public static func ==(lhs: StreamSocket, rhs: StreamSocket) -> Bool { return lhs === rhs }

    public var delegate: StreamSocketDelegate?

    public var debugDescription: String {
        return "StreamSocket(\(dsock))"
    }

    public init(socket: Socket6, delegate: StreamSocketDelegate? = nil) {
        dsock = DispatchSocket(socket: socket)
        dsock.delegate = self
    }

    public func close() {
        dsock.close()
    }

    public func dispatchSocketIsReadable(_socket: DispatchSocket, count: Int) {
        do {
            try doRead(available: count)
        } catch POSIXError(EWOULDBLOCK) {
            /* don't care */
        } catch {
            close()
            self.delegate?.streamSocketDidDisconnect(self)
            return
        }
        dsock.notifyReadable = readQueue.count > 0
    }

    public func dispatchSocketIsWritable(_socket: DispatchSocket) {
        do {
            try doWrite()
        } catch POSIXError(EWOULDBLOCK) {
            /* don't care */
        } catch {
            close()
            self.delegate?.streamSocketDidDisconnect(self)
            return
        }
        dsock.notifyWritable = writeQueue.count > 0
    }

    public func dispatchSocketDisconnected(_socket: DispatchSocket) {
        delegate?.streamSocketDidDisconnect(self)
    }

    private var readQueue: [(min: Int, max: Int, completion:(Data)->())] = []
    private var readBuffer: Data?
    private func doRead(available: Int) throws {

        guard let item = readQueue.first else { return }

        var needed = item.min
        var wanted = item.max
        if let r = readBuffer {
            needed -= r.count
            wanted -= r.count
        }

        let buf = try socket.recv(length: min(available, wanted), flags: .dontWait)
        guard buf.count > 0 else { return }

        if readBuffer != nil {
            readBuffer!.append(buf)
        } else {
            readBuffer = buf
        }

        if readBuffer!.count >= needed {
            let result = readBuffer!
            DispatchQueue.main.async { item.completion(result) }

            readBuffer = nil
            _ = readQueue.removeFirst()
        }
    }



    private var writeQueue: [Data] = []

    private func doWrite() throws {

        guard let item = writeQueue.first else { return }
        let bytesWritten = try socket.send(buffer: item, flags: .dontWait)

        if bytesWritten == item.count {
            _ = writeQueue.removeFirst()
        } else if bytesWritten > 0 {
            writeQueue[0] = item.subdata(in: bytesWritten..<item.count)
        }
    }



    public func read(_ count: Int, completion: @escaping (Data)->()) {
        guard isOpen else { return }
        readQueue.append((min: count, max: count, completion: completion))
        dsock.notifyReadable = true
    }

    public func read(max: Int, completion: @escaping (Data)->()) {
        guard isOpen else { return }
        readQueue.append((min: 1, max: max, completion: completion))
        dsock.notifyReadable = true
    }

    public func read(min: Int, max: Int, completion: @escaping (Data)->()) {
        guard isOpen else { return }
        readQueue.append((min: min, max: max, completion: completion))
        dsock.notifyReadable = true
    }

    public func write(_ data: Data) {
        guard isOpen else { return }
        writeQueue.append(data)
        dsock.notifyWritable = true
    }
}



extension StreamSocket {
    public static func connect(to address: sockaddr_in6, completion: @escaping (StreamSocket?,Error?)->()) {

        let sock = Socket6(type: .stream)

        DispatchQueue.global().async {
            do {
                try sock.connect(to: address)
                DispatchQueue.main.async {
                    completion(StreamSocket(socket: sock), nil)
                }
            } catch let err {
                DispatchQueue.main.async {
                    try? sock.close()
                    completion(nil, err)
                }
            }
        }
    }
}


public class ListenSocket : DispatchSocketDelegate {

    private var dsock: DispatchSocket?
    public var socket: Socket6? { return dsock?.socket }

    public var debugDescription: String {
        return "ListenSocket(\(dsock?.debugDescription ?? "idle"))"
    }

    public init() {}

    public func listen(port: UInt16, reuseAddress: Bool = false, accept: @escaping (Socket6)->()) throws {
        try listen(address: sockaddr_in6.any(port: port), reuseAddress: reuseAddress, accept: accept)
    }

    public func listen(address: sockaddr_in6, reuseAddress: Bool = false, accept: @escaping (Socket6)->()) throws {
        cancel()

        var s = Socket6(type: .stream)
        if reuseAddress {
            s.reuseAddress = true
        }
        try s.bind(to: address)
        dsock = DispatchSocket(socket: s, delegate: self)
        handler = accept
        try dsock!.socket.listen(backlog: 10)
        dsock!.notifyReadable = true
    }

    private var handler: ((Socket6)->())?
    public func dispatchSocketIsReadable(_socket: DispatchSocket, count: Int) {
        if let sock = dsock?.socket, let handler = handler, let newsock = try? sock.accept() {
            handler(newsock)
        }
    }

    public func dispatchSocketIsWritable(_socket: DispatchSocket) { /* don't care */ }
    public func dispatchSocketDisconnected(_socket: DispatchSocket) { /* don't care */ }

    public func cancel() {
        dsock?.close()
        dsock = nil
        handler = nil
    }

    deinit {
        cancel()
    }
}
