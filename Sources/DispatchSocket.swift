//
//  DispatchSocket.swift
//  vrtest
//
//  Created by Michael Ferenduros on 26/08/2016.
//  Copyright © 2016 Mike Ferenduros. All rights reserved.
//

import Foundation
import Dispatch



/**
    Socket6 wrapper that
     - Closes the socket on deinit
     - Invokes callbacks on readable / writable events
     - Performs async reads (one at a time)
     - Performs queued, async writes
*/
public class DispatchSocket : Hashable, CustomDebugStringConvertible {

    //Dedupe some read/write code, hide a crash-bug
    private class Source {
        var source: DispatchSourceProtocol?
        let makeSource: ()->DispatchSourceProtocol

        var eventHandler: (()->())? = nil { didSet { source?.setEventHandler(handler: eventHandler) } }

        init(makeSource: @escaping ()->DispatchSourceProtocol) {
            self.makeSource = makeSource
        }

        var running = false {
            didSet { switch (oldValue, running) {
                case (false, true):
                    if source == nil {
                        source = makeSource()
                        source?.setEventHandler(handler: self.eventHandler)
                    }
                    source!.resume()
                case (true, false):
                    source?.suspend()

                default: break
            } }
        }

        func cancel() {
            self.running = false
            self.eventHandler = nil

            //Keep source alive until cancel handler has been called :(
            var s = source
            self.source = nil
            s?.setCancelHandler { s = nil }
            s?.cancel()
        }
    }



    public let socket: Socket6
    public let type: Socket6.SocketType
    public private(set) var isOpen = true

    public var hashValue: Int { return self.socket.hashValue }
    public static func ==(lhs: DispatchSocket, rhs: DispatchSocket) -> Bool { return lhs === rhs }

    public var debugDescription: String {
        return "DispatchSocket(\(socket.debugDescription))"
    }

    private let rs, ws: Source

    public var onReadable: ((Int)->())? { didSet { self.rs.running = isOpen && (onReadable != nil) } }
    public var onWritable: (()->())?    { didSet { self.ws.running = isOpen && (onWritable != nil) } }

    public init(socket: Socket6) {
        self.socket = socket
        self.type = socket.type

        self.rs = Source { DispatchSource.makeReadSource(fileDescriptor: socket.fd, queue: DispatchQueue.main) }
        self.ws = Source { DispatchSource.makeWriteSource(fileDescriptor: socket.fd, queue: DispatchQueue.main) }

        rs.eventHandler = { [weak self] in self?.onReadable?(Int(self?.rs.source?.data ?? 0)) }
        ws.eventHandler = { [weak self] in self?.onWritable?() }
    }

    public func close() throws {
        guard isOpen else { return }
        isOpen = false
        onReadable = nil
        onWritable = nil
        writeQueue = []
        rs.cancel()
        ws.cancel()
        try socket.close()
    }

    deinit {
        try? close()
    }



    public func read(_ count: Int, completion: @escaping (Data)->()) {
        read(min: count, max: count, completion: completion)
    }

    public func read(max: Int, completion: @escaping (Data)->()) {
        read(min: 1, max: max, completion: completion)
    }

    public func read(min: Int, max: Int, completion: @escaping (Data)->()) {
        guard isOpen else { return }
        precondition(self.onReadable == nil)
        var result: Data = Data(capacity: max)

        self.onReadable = { [weak self] available in
            guard let sself = self else { return }
            guard available > 0 else { return }

            do {
                let data = try sself.socket.recv(length: max-result.count, options: .dontWait)
                if data.count > 0 {
                    result.append(data)
                    if result.count >= min {
                        sself.onReadable = nil
                        completion(result)
                    }
                }
            } catch POSIXError(EAGAIN) {
            } catch POSIXError(EWOULDBLOCK) {
            } catch {
                try? sself.close()
            }
        }
    }


    private var writeQueue: [Data] = []

    public func write(_ data: Data) {
        guard isOpen else { return }
        writeQueue.append(data)

        self.onWritable = { [weak self] in
            guard let sself = self else { return }
            do {
                while let packet = sself.writeQueue.first {
                    let written = try sself.socket.send(buffer: packet, options: .dontWait)
                    if written == packet.count || sself.type == .datagram {
                        //Datagrams are truncated to whatever gets accepted by a single send()
                        _ = sself.writeQueue.removeFirst()
                    } else {
                        //For streams, we try and send the entire packet, even if it takes multiple calls
                        sself.writeQueue[0] = packet.subdata(in: written ..< packet.count)
                        break
                    }
                }
            } catch POSIXError(EAGAIN) {
            } catch POSIXError(EWOULDBLOCK) {
            } catch {
                try? self?.close()
            }
        }
    }
}
