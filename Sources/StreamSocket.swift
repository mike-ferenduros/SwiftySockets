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
public class StreamSocket : CustomDebugStringConvertible {

    public let socket: Socket6

    private let rsource: DispatchSourceRead
    private let wsource: DispatchSourceWrite
    public var delegate: StreamSocketDelegate?

    public private(set) var isOpen = true

    public var debugDescription: String {
        return "\(isOpen ? "Open" : "Closed") StreamSocket \(socket)"
    }

    public init(socket: Socket6, delegate: StreamSocketDelegate? = nil) {
        self.socket = socket
        self.delegate = delegate
        rsource = DispatchSource.makeReadSource(fileDescriptor: self.socket.fd, queue: DispatchQueue.main)
        wsource = DispatchSource.makeWriteSource(fileDescriptor: self.socket.fd, queue: DispatchQueue.main)

        rsource.setEventHandler { [weak self] in self?.tryRead() }
        wsource.setEventHandler { [weak self] in self?.tryWrite() }
    }

    private var wantReadEvents = false {
        didSet {
            guard isOpen else { return }
            switch (oldValue, wantReadEvents) {
                case (true, false): rsource.suspend()
                case (false, true): rsource.resume()
                default: break
            }
        }
    }

    private var wantWriteEvents = false {
        didSet {
            guard isOpen else { return }
            switch (oldValue, wantWriteEvents) {
                case (true, false): wsource.suspend()
                case (false, true): wsource.resume()
                default: break
            }
        }
    }

    deinit {
        close()
    }
    
    private func didDisconnect() {
        close()
        self.delegate?.streamSocketDidDisconnect(self)
    }

    public func close() {
        if isOpen {
            rsource.cancel()
            wsource.cancel()
            try? socket.close()
            readQueue.removeAll()
            writeQueue.removeAll()
            readBuffer = nil
            isOpen = false
        }
    }


    private var readQueue: [(min: Int, max: Int, completion:(Data)->())] = []
    private var readBuffer: Data?
    private func tryRead() {

        guard isOpen, let item = readQueue.first else { return }

        var needed = item.min
        var wanted = item.max
        if let r = readBuffer {
            needed -= r.count
            wanted -= r.count
        }

        var buf = Data(count: wanted)
        do {
            let bytesRead = try buf.withUnsafeMutableBytes { return try socket.recv(buffer: $0, length: buf.count, flags: .dontWait) }

            if bytesRead <= 0 {
                didDisconnect()
                return
            }

            if bytesRead < buf.count {
                buf = buf.subdata(in: 0..<bytesRead)
            }

            if readBuffer != nil {
                readBuffer!.append(buf)
            } else {
                readBuffer = buf
            }

            if readBuffer!.count >= needed {
                let result = readBuffer!
                readBuffer = nil
                _ = readQueue.removeFirst()
                item.completion(result)
            }

            wantReadEvents = readQueue.count > 0

        } catch let e {
            if let pe = e as? POSIXError, [EWOULDBLOCK,EAGAIN].contains(pe.code) {
                wantReadEvents = true
            } else {
                didDisconnect()
            }
        }
    }



    private var writeQueue: [Data] = []

    private func tryWrite() {

        guard isOpen, let item = writeQueue.first else { return }

        do {
            let bytesWritten = try item.withUnsafeBytes { return try socket.send(buffer: $0, length: item.count, flags: .dontWait) }

            if bytesWritten == item.count {
                _ = writeQueue.removeFirst()
            } else if bytesWritten > 0 {
                writeQueue[0] = item.subdata(in: bytesWritten..<item.count)
            }
            wantWriteEvents = writeQueue.count > 0
        } catch let e {
            if let pe = e as? POSIXError, [EWOULDBLOCK,EAGAIN].contains(pe.code) {
                wantWriteEvents = true
            } else {
                didDisconnect()
            }
        }
    }

    public func read(_ count: Int, completion: @escaping (Data)->()) {
        guard isOpen else { return }
        readQueue.append((min: count, max: count, completion: completion))
        wantReadEvents = true
    }

    public func read(max: Int, completion: @escaping (Data)->()) {
        guard isOpen else { return }
        readQueue.append((min: 1, max: max, completion: completion))
        wantReadEvents = true
    }

    public func read(min: Int, max: Int, completion: @escaping (Data)->()) {
        guard isOpen else { return }
        readQueue.append((min: min, max: max, completion: completion))
        wantReadEvents = true
    }

    public func write(_ data: Data) {
        guard isOpen else { return }
        writeQueue.append(data)
        wantWriteEvents = true
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


public class ListenSocket : CustomDebugStringConvertible {

    private var socket: Socket6?
    private var source: DispatchSourceRead?
    
    public var debugDescription: String {
        return "ListenSocket \(socket?.debugDescription ?? "idle")"
    }

    public init() {
        //default init() is internal, not public
    }

    public func listen(port: UInt16, reuseAddress: Bool = false, accept: @escaping (Socket6)->()) throws {
        try listen(address: sockaddr_in6.any(port: port), reuseAddress: reuseAddress, accept: accept)
    }

    public func listen(address: sockaddr_in6, reuseAddress: Bool = false, accept: @escaping (Socket6)->()) throws {
        cancel()

        socket = Socket6(type: .stream)
        if reuseAddress {
            try? socket!.setsockopt(SOL_SOCKET, SO_REUSEADDR, UInt32(1))
        }
        try socket!.bind(to: address)

        source = DispatchSource.makeReadSource(fileDescriptor: socket!.fd, queue: DispatchQueue.main)
        source!.setEventHandler { [weak self] in
            if let sock = self?.socket, let newsock = try? sock.accept() {
                accept(newsock)
            }
        }
        source?.setCancelHandler { [weak self] in
            self?.source = nil
            self?.cancel()
        }
        source?.resume()
        try socket?.listen(backlog: 10)
    }

    public func cancel() {
        source?.cancel()
        try? socket?.close()
        source = nil
        socket = nil
    }

    deinit {
        cancel()
    }
}
