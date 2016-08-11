//
//  StreamSocket.swift
//  SwiftySockets
//
//  Created by Michael Ferenduros on 03/08/2016.
//  Copyright © 2016 Mike Ferenduros. All rights reserved.
//

import Foundation


/**
    Buffered, async TCP with SSL support.
    Requires a running RunLoop.main to function.
*/
public class StreamSocket : NSObject, StreamDelegate {

    public let socket: Socket6

    private let istream: InputStream
    private let ostream: NSOutputStream
    private var canRead = false
    private var canWrite = false

    public private(set) var isOpen = true

    public init(socket: Socket6) {
        self.socket = socket

        var cfistream: Unmanaged<CFReadStream>?
        var cfostream: Unmanaged<CFWriteStream>?
        CFStreamCreatePairWithSocket(nil, self.socket.fd, &cfistream, &cfostream)

        self.istream = cfistream!.takeRetainedValue()
        self.ostream = cfostream!.takeRetainedValue()

        super.init()

        istream.delegate = self
        ostream.delegate = self

        istream.schedule(in: RunLoop.current, forMode: RunLoopMode.commonModes)
        ostream.schedule(in: RunLoop.current, forMode: RunLoopMode.commonModes)

        istream.open()
        ostream.open()
    }

    public static func connect(to address: sockaddr_in6, completion: (StreamSocket?,Error?)->()) {

        let sock = Socket6(type: SOCK_STREAM)

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

    deinit {
        close()
    }

    public func close() {
        if isOpen {
            istream.close()
            ostream.close()
            istream.delegate = nil
            ostream.delegate = nil
            try? socket.close()
            isOpen = false
        }
    }



    public func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        guard isOpen else { return }
        if eventCode.contains(.hasBytesAvailable) {
            canRead = true
            tryRead()
        }
        if eventCode.contains(.hasSpaceAvailable) {
            canWrite = true
            tryWrite()
        }
        if eventCode.contains(.endEncountered) || eventCode.contains(.errorOccurred) {
            close()
        }
    }


    private var readQueue: [(min: Int, max: Int, completion:(Data?)->())] = []
    private var readBuffer: Data?
    private func tryRead() {
        guard isOpen else { return }
        guard let item = readQueue.first, canRead else { return }

        var needed = item.min
        var wanted = item.max
        if let r = readBuffer {
            needed -= r.count
            wanted -= r.count
        }

        var buf = Data(count: wanted)
        canRead = false
        let bytesRead = buf.withUnsafeMutableBytes { return istream.read($0, maxLength: buf.count) }
        if bytesRead == 0 { return }
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
        guard isOpen else { return }
        guard let item = writeQueue.first, canWrite else { return }

        canWrite = false
        let bytesWritten = item.withUnsafeBytes { return ostream.write($0, maxLength: item.count) }

        if bytesWritten == item.count {
            _ = writeQueue.removeFirst()
        } else if bytesWritten > 0 {
            writeQueue[0] = item.subdata(in: bytesWritten..<item.count)
        }
    }

    public func read(_ count: Int, completion: (Data?)->()) {
        guard Thread.isMainThread else { fatalError() }
        readQueue.append((min: count, max: count, completion: completion))
        self.tryRead()
    }

    public func read(max: Int, completion: (Data?)->()) {
        readQueue.append((min: 1, max: max, completion: completion))
        tryRead()
    }

    public func read(min: Int, max: Int, completion: (Data?)->()) {
        readQueue.append((min: min, max: max, completion: completion))
        tryRead()
    }

    public func write(_ data: Data) {
        writeQueue.append(data)
        tryWrite()
    }
}


class ListenSocket {

    private(set) var socket: Socket6?
    private var source: DispatchSourceRead?

    func listen(port: UInt16, accept: (Socket6)->()) throws {
        try listen(address: sockaddr_in6.any(port: port), accept: accept)
    }

    func listen(address: sockaddr_in6, accept: (Socket6)->()) throws {
        if socket != nil || source != nil {
            cancel()
        }

        socket = Socket6(type: SOCK_STREAM)
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
        source?.activate()
        try socket?.listen(backlog: 10)
    }

    func cancel() {
        source?.cancel()
        try? socket?.close()
        source = nil
        socket = nil
    }

    deinit {
        cancel()
    }
}
