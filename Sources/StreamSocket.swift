//
//  StreamSocket.swift
//  SwiftySockets
//
//  Created by Michael Ferenduros on 03/08/2016.
//  Copyright © 2016 Mike Ferenduros. All rights reserved.
//

import Foundation
import Dispatch
import CoreFoundation


public protocol StreamSocketDelegate {
    func streamSocketDidDisconnect(_ socket: StreamSocket)
}


/**
    Buffered, async TCP
*/
public class StreamSocket : CustomDebugStringConvertible {

    public let socket: Socket6

    private let rstream: CFReadStream
    private let wstream: CFWriteStream
    private var canRead = false
    private var canWrite = false
    public var delegate: StreamSocketDelegate?

    public private(set) var isOpen = true

    public var debugDescription: String {
        return "\(isOpen ? "Open" : "Closed") StreamSocket \(socket)"
    }

    public init(socket: Socket6, delegate: StreamSocketDelegate? = nil) {
        self.socket = socket

        self.delegate = delegate

        var urstream: Unmanaged<CFReadStream>?
        var uwstream: Unmanaged<CFWriteStream>?
        CFStreamCreatePairWithSocket(nil, self.socket.fd, &urstream, &uwstream)
        rstream = urstream!.takeRetainedValue()
        wstream = uwstream!.takeRetainedValue()

        let pself = Unmanaged.passUnretained(self).toOpaque()
        var callbackContext = CFStreamClientContext(version: 0, info: pself, retain: nil, release: nil, copyDescription: nil)

        let rcallback: CFReadStreamClientCallBack = { _, event, info in
            let iself = (Unmanaged.fromOpaque(info!) as Unmanaged<StreamSocket>).takeUnretainedValue()
            iself.handle(event: event)
        }

        let wcallback: CFWriteStreamClientCallBack = { _, event, info in
            let iself = (Unmanaged.fromOpaque(info!) as Unmanaged<StreamSocket>).takeUnretainedValue()
            iself.handle(event: event)
        }

        #if os(Linux)
        let revents = kCFStreamEventHasBytesAvailable | kCFStreamEventErrorOccurred | kCFStreamEventEndEncountered
        let wevents = kCFStreamEventCanAcceptBytes | kCFStreamEventErrorOccurred | kCFStreamEventEndEncountered
        CFReadStreamSetClient(rstream, CFStreamEventType(revents), rcallback, &callbackContext)
        CFWriteStreamSetClient(wstream, CFStreamEventType(wevents), wcallback, &callbackContext)
        #else
        let revents: CFStreamEventType = [.hasBytesAvailable, .errorOccurred, .endEncountered]
        let wevents: CFStreamEventType = [.canAcceptBytes, .errorOccurred, .endEncountered]
        CFReadStreamSetClient(rstream, revents.rawValue, rcallback, &callbackContext)
        CFWriteStreamSetClient(wstream, wevents.rawValue, wcallback, &callbackContext)
        #endif

        #if os(Linux)
        let commonModes = kCFRunLoopCommonModes
        #else
        let commonModes = CFRunLoopMode.commonModes
        #endif
        CFReadStreamScheduleWithRunLoop(rstream, CFRunLoopGetCurrent(), commonModes)
        CFWriteStreamScheduleWithRunLoop(wstream, CFRunLoopGetCurrent(), commonModes)

        CFReadStreamOpen(rstream)
        CFWriteStreamOpen(wstream)
    }

    private func handle(event: CFStreamEventType) {
        guard isOpen else { return }

        #if os(Linux)
        let readEvent = (event & CFStreamEventType(kCFStreamEventHasBytesAvailable)) != 0
        let writeEvent = (event & CFStreamEventType(kCFStreamEventCanAcceptBytes)) != 0
        let closedEvent = (event & CFStreamEventType(kCFStreamEventErrorOccurred | kCFStreamEventEndEncountered)) != 0
        #else
        let readEvent = event.contains(.hasBytesAvailable)
        let writeEvent = event.contains(.canAcceptBytes)
        let closedEvent = event.contains(.endEncountered) || event.contains(.errorOccurred)
        #endif

        if readEvent {
            canRead = true
            tryRead()
        }
        if writeEvent {
            canWrite = true
            tryWrite()
        }
        if closedEvent {
            close()
            self.delegate?.streamSocketDidDisconnect(self)
        }
    }

    deinit {
        CFReadStreamSetClient(rstream, 0, nil, nil)
        CFWriteStreamSetClient(wstream, 0, nil, nil)
        close()
    }

    public func close() {
        if isOpen {
            CFReadStreamClose(rstream)
            CFWriteStreamClose(wstream)
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

        guard isOpen, let item = readQueue.first, canRead else { return }

        var needed = item.min
        var wanted = item.max
        if let r = readBuffer {
            needed -= r.count
            wanted -= r.count
        }

        var buf = Data(count: wanted)
        canRead = false
        let bytesRead = buf.withUnsafeMutableBytes { return CFReadStreamRead(rstream, $0, buf.count) }
        if bytesRead <= 0 { return }
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
            item.completion(result)

            readBuffer = nil
            _ = readQueue.removeFirst()
        }
    }



    private var writeQueue: [Data] = []

    private func tryWrite() {

        guard isOpen, let item = writeQueue.first, canWrite else { return }

        canWrite = false
        let bytesWritten = item.withUnsafeBytes { return CFWriteStreamWrite(wstream, $0, item.count) }

        if bytesWritten == item.count {
            _ = writeQueue.removeFirst()
        } else if bytesWritten > 0 {
            writeQueue[0] = item.subdata(in: bytesWritten..<item.count)
        }
    }

    public func read(_ count: Int, completion: @escaping (Data)->()) {
        guard isOpen else { return }
        readQueue.append((min: count, max: count, completion: completion))
        tryRead()
    }

    public func read(max: Int, completion: @escaping (Data)->()) {
        guard isOpen else { return }
        readQueue.append((min: 1, max: max, completion: completion))
        tryRead()
    }

    public func read(min: Int, max: Int, completion: @escaping (Data)->()) {
        guard isOpen else { return }
        readQueue.append((min: min, max: max, completion: completion))
        tryRead()
    }

    public func write(_ data: Data) {
        guard isOpen else { return }
        writeQueue.append(data)
        tryWrite()
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

    private(set) public var socket: Socket6?
    private var source: DispatchSourceRead?
    
    public var debugDescription: String {
        return "ListenSocket \(socket?.debugDescription ?? "idle")"
    }

    public init() {
        //default init() is internal, not public
    }

    public func listen(port: UInt16, accept: @escaping (Socket6)->()) throws {
        try listen(address: sockaddr_in6.any(port: port), accept: accept)
    }

    public func listen(address: sockaddr_in6, accept: @escaping (Socket6)->()) throws {
        cancel()

        socket = Socket6(type: .stream)
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
