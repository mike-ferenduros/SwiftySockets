//
//  BufferedSocket.swift
//  SwiftySockets
//
//  Created by Michael Ferenduros on 11/09/2016.
//  Copyright © 2016 Mike Ferenduros. All rights reserved.
//

import Foundation


open class BufferedSocket : DispatchSocket, DispatchSocketReadableDelegate, DispatchSocketWritableDelegate {

    override public var debugDescription: String {
        return "BufferedSocket(\(socket.debugDescription))"
    }

    override open func close() throws {
        readQueue.removeAll()
        writeQueue.removeAll()
        try super.close()
    }

    /**
    Read exactly `count` bytes.
    - Parameter count: Number of bytes to read
    - Parameter completion: Completion-handler, invoked on DispatchQueue.main on success
    */
    public func read(_ count: Int, completion: @escaping (Data)->()) {
        read(min: count, max: count, completion: completion)
    }

    /**
    Read up to `max` bytes
    - Parameter max: Maximum number of bytes to read
    - Parameter completion: Completion-handler, invoked on DispatchQueue.main on success
    */
    public func read(max: Int, completion: @escaping (Data)->()) {
        read(min: 1, max: max, completion: completion)
    }

    /**
    Read at least `min` bytes, up to `max` bytes
    - Parameter min: Minimum number of bytes to read
    - Parameter min: Maximum number of bytes to read
    - Parameter completion: Completion-handler, invoked on DispatchQueue.main on success
    */
    public func read(min: Int, max: Int, completion: @escaping (Data)->()) {
        precondition(min <= max)
        precondition(min > 0)
        guard isOpen else { return }
        let newItem = ReadItem(buffer: Data(capacity: max), min: min, max: max, completion: completion)
        readQueue.append(newItem)
        readableDelegate = self
    }


    private struct ReadItem {
        var buffer: Data
        let min, max: Int
        let completion: (Data)->()
    }
    private var readQueue: [ReadItem] = []

    public func dispatchSocketReadable(_ socket: DispatchSocket, count: Int) {

        guard count > 0 else { try? close(); return }

        do {
            while var item = readQueue.first {
                let wanted = item.max - item.buffer.count
                let buffer = try self.socket.recv(length: min(wanted, count), options: .dontWait)
                item.buffer.append(buffer)
                readQueue[0] = item

                if item.buffer.count >= item.min {
                    readQueue.removeFirst()
                    item.completion(item.buffer)
                } else {
                    break
                }
            }
        }
        catch POSIXError(EAGAIN) {}
        catch POSIXError(EWOULDBLOCK) {}
        catch {
            try? close()
        }

        if readQueue.count == 0 {
            readableDelegate = nil
        }
    }



    private var writeQueue: [Data] = []

    /**
    Asynchronously write data to the connected socket.
    For stream-type sockets, the entire contents of `data` is always written
    For datagram-type sockets, only a single datagram is sent, hence the data may be truncated.
     - Parameter data: Data to be written.
    */
    public func write(_ data: Data) {
        guard isOpen else { return }
        var data = data

        //Try and shortcut the whole dispatch-source stuff if possible.
        if writeQueue.count == 0, let written = try? self.socket.send(buffer: data, options: .dontWait), written > 0 {
            if written == data.count || self.type == .datagram {
                return
            } else {
                data = data.subdata(in: written ..< data.count)
            }
        }

        writeQueue.append(data)
        writableDelegate = self
    }

    public func dispatchSocketWritable(_ socket: DispatchSocket) {
        do {
            while let packet = writeQueue.first {
                let written = try self.socket.send(buffer: packet, options: .dontWait)
                if written == packet.count || self.type == .datagram {
                    //Datagrams are truncated to whatever gets accepted by a single send()
                    _ = writeQueue.removeFirst()
                } else {
                    if written > 0 {
                        //For streams, we try and send the entire packet, even if it takes multiple calls
                        writeQueue[0] = packet.subdata(in: written ..< packet.count)
                    }
                    break
                }
            }
        } catch POSIXError(EAGAIN) {
        } catch POSIXError(EWOULDBLOCK) {
        } catch {
            try? close()
            return
        }
        if writeQueue.count == 0 {
            writableDelegate = nil
        }
    }
}
