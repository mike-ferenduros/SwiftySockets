//
//  DispatchSocket.swift
//  vrtest
//
//  Created by Michael Ferenduros on 26/08/2016.
//  Copyright © 2016 Mike Ferenduros. All rights reserved.
//

import Foundation
import Dispatch


public protocol DispatchSocketReadableDelegate : class {
    func dispatchSocketReadable(_ socket: DispatchSocket, count: Int)
}

public protocol DispatchSocketWritableDelegate : class {
    func dispatchSocketWritable(_ socket: DispatchSocket)
}


/**
    Socket6 wrapper that
     - Closes the socket on deinit
     - Invokes delegate methods on readable / writable events
*/
open class DispatchSocket : Hashable, CustomDebugStringConvertible {

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

    public weak var readableDelegate : DispatchSocketReadableDelegate? { didSet { rs.running = isOpen && (readableDelegate != nil) } }
    public weak var writableDelegate : DispatchSocketWritableDelegate? { didSet { ws.running = isOpen && (writableDelegate != nil) } }

    public init(socket: Socket6) {
        self.socket = socket
        self.type = socket.type

        self.rs = Source { DispatchSource.makeReadSource(fileDescriptor: socket.fd, queue: DispatchQueue.main) }

        #if os(Linux)
        //This is suck. Linux doesn't support both readable and writable sources on the same fd, so we have to fake up one of them.
        self.ws = Source {
            let s = DispatchSource.makeTimerSource(flags: [], queue: DispatchQueue.main)
            s.scheduleRepeating(deadline: DispatchTime.now(), interval: 0.01)
            return s
        }
        #else
        self.ws = Source { DispatchSource.makeWriteSource(fileDescriptor: socket.fd, queue: DispatchQueue.main) }
        #endif

        rs.eventHandler = { [weak self] in self?.readableDelegate?.dispatchSocketReadable(self!, count: Int(self!.rs.source?.data ?? 0)) }
        ws.eventHandler = { [weak self] in self?.writableDelegate?.dispatchSocketWritable(self!) }
    }

     open func close() throws {
        guard isOpen else { return }
        isOpen = false
        self.readableDelegate = nil
        self.writableDelegate = nil
        rs.cancel()
        ws.cancel()
        try socket.close()
    }

    deinit {
        try? close()
    }
}
