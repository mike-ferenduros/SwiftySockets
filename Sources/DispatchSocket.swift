//
//  DispatchSocket.swift
//  vrtest
//
//  Created by Michael Ferenduros on 26/08/2016.
//  Copyright © 2016 Mike Ferenduros. All rights reserved.
//

import Foundation
import Dispatch

public protocol DispatchSocketDelegate : class {
    func dispatchSocketIsReadable(_socket: DispatchSocket, count: Int)
    func dispatchSocketIsWritable(_socket: DispatchSocket)
    func dispatchSocketDisconnected(_socket: DispatchSocket)
}

/**
    Socket6 wrapper that
     - Closes the socket on deinit
     - Notifies a delegate on readable / writable / disconnect events

    Readable and disconnect delegate methods are dispatched only when notifyReadable=true (default false)
    Writable delegate methods are dispatched only when notifyWritable=true (default false)
    If enabled, readable / writable methods are called repeatedly, on the main queue, so long as the socket is readable / writable
*/
public class DispatchSocket : Hashable, CustomDebugStringConvertible {

    public let socket: Socket6
    public weak var delegate: DispatchSocketDelegate?
    public private(set) var isOpen = true

    public var hashValue: Int { return self.socket.hashValue }
    public static func ==(lhs: DispatchSocket, rhs: DispatchSocket) -> Bool { return lhs === rhs }

    public var debugDescription: String {
        return "DispatchSocket(\(socket.debugDescription))"
    }

    private let rsource: DispatchSourceRead
    private let wsource: DispatchSourceWrite

    ///Also controls whether delegate gets disconnected events
    public var notifyReadable: Bool = false {
        didSet {
            guard isOpen else { return }
            switch (oldValue, notifyReadable) {
                case (false, true): rsource.resume()
                case (true, false): rsource.suspend()
                default: return
            }
        }
    }

    public var notifyWritable: Bool = false {
        didSet {
            guard isOpen else { return }
            switch (oldValue, notifyWritable) {
                case (false, true): wsource.resume()
                case (true, false): wsource.suspend()
                default: return
            }
        }
    }

    public init(socket: Socket6, delegate: DispatchSocketDelegate? = nil) {
        self.socket = socket
        self.delegate = delegate
        rsource = DispatchSource.makeReadSource(fileDescriptor: socket.fd, queue: DispatchQueue.main)
        wsource = DispatchSource.makeWriteSource(fileDescriptor: socket.fd, queue: DispatchQueue.main)

        rsource.setEventHandler { [weak self] in
            guard let sself = self, sself.isOpen, let delegate = sself.delegate else { return }
            if sself.rsource.data > 0 {
                delegate.dispatchSocketIsReadable(_socket: sself, count: Int(sself.rsource.data))
            } else {
                delegate.dispatchSocketDisconnected(_socket: sself)
            }
        }

        wsource.setEventHandler { [weak self] in
            guard let sself = self, sself.isOpen, let delegate = sself.delegate else { return }
            delegate.dispatchSocketIsWritable(_socket: sself)
        }
    }

    public func close() {
        guard isOpen else { return }

        //Sigh. Ensure sources are kept alive until cancellation handler has been called.
        var rs: DispatchSourceRead? = rsource
        var ws: DispatchSourceWrite? = wsource
        rsource.setCancelHandler { _ = rs?.handle; rs = nil }   //Access a property to shut the bloody compiler up,
        wsource.setCancelHandler { _ = ws?.handle; ws = nil }   //and to ensure the var isn't optimised away.
        rsource.setEventHandler(handler: nil)
        wsource.setEventHandler(handler: nil)
        self.notifyReadable = true
        self.notifyWritable = true
        rsource.cancel()
        wsource.cancel()

        try? socket.close()

        isOpen = false
    }

    deinit {
        close()
    }
}
