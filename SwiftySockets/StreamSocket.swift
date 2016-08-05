//
//  StreamSocket.swift
//  SwiftySockets
//
//  Created by Michael Ferenduros on 03/08/2016.
//  Copyright © 2016 Mike Ferenduros. All rights reserved.
//

import Foundation


public class StreamSocket : NSObject, StreamDelegate {

    public let socket: Socket6

    private let queue = DispatchQueue(label: "StreamSocket")
    private let istream: InputStream
    private let ostream: NSOutputStream

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

        istream.schedule(in: RunLoop.main, forMode: RunLoopMode.commonModes)
        ostream.schedule(in: RunLoop.main, forMode: RunLoopMode.commonModes)

        queue.async {
            self.istream.open()
            self.ostream.open()
            self.tryRead()
            self.tryWrite()
        }
    }

    public static func connect(to address: sockaddr_in6, completion: (StreamSocket?,NSError?)->()) {

        let sock = Socket6(type: SOCK_STREAM)

        DispatchQueue.global().async {
            do {
                try sock.connect(to: address)
                DispatchQueue.main.async {
                    completion(StreamSocket(socket: sock), nil)
                }
            } catch let err as NSError {
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
        istream.close()
        ostream.close()
        istream.delegate = nil
        ostream.delegate = nil
        isOpen = false
    }



    public func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        guard isOpen else { return }
        if eventCode.contains(.hasBytesAvailable) {
            queue.async { self.tryRead() }
        }
        if eventCode.contains(.hasSpaceAvailable) {
            queue.async { self.tryWrite() }
        }
        if eventCode.contains(.endEncountered) || eventCode.contains(.errorOccurred) {
            close()
        }
    }


    private var readQueue: [(min: Int, max: Int, completion:(Data?)->())] = []
    private var readBuffer: Data?
    private func tryRead() {
        guard isOpen else { return }
        if let item = readQueue.first, istream.hasBytesAvailable {
            var needed = item.min
            var wanted = item.max
            if let r = readBuffer {
                needed -= r.count
                wanted -= r.count
            }

            var buf = Data(count: wanted)
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
                DispatchQueue.main.async { item.completion(result) }

                readBuffer = nil
                _ = readQueue.removeFirst()
            }

            //Go again?
            if bytesRead == wanted && readQueue.count > 0 {
                queue.async { self.tryRead() }
            }
        }
    }



    private var writeQueue: [Data] = []

    private func tryWrite() {
        guard isOpen, let item = writeQueue.first, ostream.hasSpaceAvailable else { return }

        let bytesWritten = item.withUnsafeBytes { return ostream.write($0, maxLength: item.count) }

        if bytesWritten == item.count {
            _ = writeQueue.removeFirst()

            //Go again?
            if writeQueue.count > 0 {
                self.queue.async { self.tryWrite() }
            }
        } else {
            //Partial write - update queued item
            writeQueue[0] = item.subdata(in: bytesWritten..<item.count)
        }
    }

    public func read(_ count: Int, completion: (Data?)->()) {
        queue.async {
            self.readQueue.append((min: count, max: count, completion: completion))
            self.tryRead()
        }
    }

    public func read(max: Int, completion: (Data?)->()) {
        queue.async {
            self.readQueue.append((min: 1, max: max, completion: completion))
            self.tryRead()
        }
    }

    public func read(min: Int, max: Int, completion: (Data?)->()) {
        queue.async {
            self.readQueue.append((min: min, max: max, completion: completion))
            self.tryRead()
        }
    }

    public func write(_ data: Data) {
        queue.async {
            self.writeQueue.append(data)
            self.tryWrite()
        }
    }
}



extension Socket6 {

    public func listen(acceptHandler: (Socket6)->()) throws {
        try listen()
        DispatchQueue.global().async {
            while let newsock = try? self.accept() {
                DispatchQueue.main.async { acceptHandler(newsock) }
            }
        }
    }
}
