//
//  SecureTransportSocket.swift
//  SwiftySockets
//
//  Created by Michael Ferenduros on 12/09/2016.
//  Copyright © 2016 Mike Ferenduros. All rights reserved.
//

import Foundation
import Security


private class SecureTransportCertificate : SecureSocketCertificate {
    required public init?(key: Data, certs: [Data]) {
        #if os(OSX)
        var chain: [AnyObject]

        var cfkeys: CFArray?
        guard SecItemImport(key as CFData, nil, nil, nil, [], nil, nil, &cfkeys) == noErr else { return nil }
        guard let keys = (cfkeys as [AnyObject]?), keys.count == 1, CFGetTypeID(keys[0]) == SecIdentityGetTypeID() else { return nil }
        chain = [keys[0]]

        for certs in certs {
            var cfitems: CFArray?
            guard SecItemImport(certs as CFData, nil, nil, nil, [], nil, nil, &cfitems) == noErr else { return nil }
            guard let items = (cfitems as [AnyObject]?) else { return nil }
            let certitems = items.filter { CFGetTypeID($0) == SecCertificateGetTypeID() }
            chain.append(contentsOf: certitems)
        }

        certificateChain = chain as CFArray
        #else
        assertionFailure("Sorry, certificates aren't supported on iOS platforms.")
        #endif
    }

    let certificateChain: CFArray
}



public class SecureTransportSocket : DispatchSocket, SecureSocket, DispatchSocketReadableDelegate, DispatchSocketWritableDelegate {

    public weak var delegate: SecureSocketDelegate?
    public private(set) var certificate: SecureSocketCertificate?
    static public let CertificateType: SecureSocketCertificate.Type? = SecureTransportCertificate.self


    //context gets an unretained pointer to us, take care not to let it dangle
    private var context: SSLContext? {
        willSet { if let context = context { SSLSetConnection(context, nil) } }
        didSet { if let context = context { SSLSetConnection(context, Unmanaged.passUnretained(self).toOpaque()) } }
    }

    deinit {
        self.context = nil
    }

    required public init(socket: Socket6, side: SecureSocketSide, certificate: SecureSocketCertificate?) {

        precondition(socket.type == .stream)

        let pside: SSLProtocolSide = (side == .client) ? .clientSide : .serverSide
        if let certificate = certificate {
            assert(certificate is SecureTransportCertificate)
            self.certificate = certificate as? SecureTransportCertificate
        } else {
            assert(pside == .clientSide)
        }

        self.context = SSLCreateContext(nil, pside, .streamType)

        if let cert = self.certificate {
            SSLSetCertificate(context!, (cert as! SecureTransportCertificate).certificateChain)
        }

        SSLSetIOFuncs(context!,
            { (pself, buffer, pcount) -> OSStatus in
                let sself = Unmanaged<SecureTransportSocket>.fromOpaque(pself).takeUnretainedValue()
                return sself.handleWrite(buffer: buffer, pcount: pcount)
            },
            { (pself, buffer, pcount) -> OSStatus in
                let sself = Unmanaged<SecureTransportSocket>.fromOpaque(pself).takeUnretainedValue()
                return sself.handleWrite(buffer: buffer, pcount: pcount)
            }
        )

        super.init(socket: socket)
    }

    override open func close() throws {
        readQueue.removeAll()
        writeQueue.removeAll()
        self.context = nil
        try super.close()
    }

    private func handleRead(buffer: UnsafeMutableRawPointer, pcount: UnsafeMutablePointer<Int>) -> OSStatus {
        do {
            let count = pcount.pointee
            let received = try self.socket.recv(buffer: buffer, length: count, options: .dontWait)
            pcount.pointee = received
            if received == count {
                readBlocked = false
                return noErr
            } else if received == 0 {
                //Connection was closed at the other end
                try? close()
            }
        }
        catch POSIXError(EWOULDBLOCK) {}
        catch POSIXError(EAGAIN) {}
        catch { try? close() }

        readBlocked = true
        return errSSLWouldBlock
    }

    private func handleWrite(buffer: UnsafeRawPointer, pcount: UnsafeMutablePointer<Int>) -> OSStatus {
        do {
            let count = pcount.pointee
            let sent = try self.socket.send(buffer: buffer, length: count, options: .dontWait)
            pcount.pointee = sent
            if sent == count {
                writeBlocked = false
                return noErr
            }
        }
        catch POSIXError(EWOULDBLOCK) {}
        catch POSIXError(EAGAIN) {}
        catch { try? close() }

        writeBlocked = true
        return errSSLWouldBlock
    }

    private var readBlocked = false { didSet { if readBlocked != oldValue { updateDelegates() } } }
    private var writeBlocked = false { didSet { if writeBlocked != oldValue { updateDelegates() } } }
    
    private func updateDelegates() {
        self.readableDelegate = (isOpen && readBlocked) ? self : nil
        self.writableDelegate = (isOpen && writeBlocked) ? self : nil
    }

    private var handshakeComplete = false


    public func dispatchSocketReadable(_ socket: DispatchSocket, count: Int) {
        if count == 0 {
            try? self.close()
            self.delegate?.secureSocketDidDisconnect(self)
        } else {
            pumpQueues()
        }
    }

    public func dispatchSocketWritable(_ socket: DispatchSocket) {
        pumpQueues()
    }
    
    private func pumpQueues() {
        guard checkHandshake() else { return }
        pumpReads()
        pumpWrites()
    }

    private func checkHandshake() -> Bool {
        guard isOpen, let context = context else { return false }
        if handshakeComplete { return true }
        let result = SSLHandshake(context)
        switch result {
            case noErr:
                handshakeComplete = true
                self.delegate?.secureSocketHandshakeDidSucceed(self)
                return true

            case errSSLPeerAuthCompleted:
                //Nearly there, keep going...
                return checkHandshake()

            case errSSLWouldBlock:
                //Wait for readable/writable handler to kick in and trigger this again
                return false

            default:
                let errors: [OSStatus:SecureSocketError] = [errSSLUnknownRootCert:.invalidCert, errSSLNoRootCert: .invalidCert, errSSLCertExpired: .expiredCert]
                let error = errors[result] ?? .unknown
                self.delegate?.secureSocketHandshakeDidFail(self, with: error)
                return false
        }
    }


    private struct ReadItem {
        var buffer: Data
        let min, max: Int
        let completion: (Data)->()
    }

    private var readQueue: [ReadItem] = []

    public func read(min: Int, max: Int, completion: @escaping (Data)->()) {
        precondition(min <= max)
        precondition(min > 0)
        guard isOpen else { return }
        let newItem = ReadItem(buffer: Data(capacity: max), min: min, max: max, completion: completion)
        readQueue.append(newItem)
        pumpQueues()
    }

    private func pumpReads() {
        while var item = readQueue.first, isOpen {
            let wanted = item.max - item.buffer.count
            var buffer = Data(count: wanted)
            var bytesRead: Int = 0
            buffer.withUnsafeMutableBytes { _ = SSLRead(context!, $0, wanted, &bytesRead) }
            if bytesRead == wanted {
                item.buffer.append(buffer)
            } else if bytesRead > 0 {
                item.buffer.append(buffer.subdata(in: 0 ..< bytesRead))
            } else {
                break
            }
            readQueue[0] = item

            if item.buffer.count >= item.min {
                readQueue.removeFirst()
                item.completion(item.buffer)
            } else {
                break
            }
        }
    }


    private var writeQueue: [Data] = []

    public func write(_ data: Data) {
        guard isOpen else { return }
        writeQueue.append(data)
        pumpQueues()
    }
    
    private func pumpWrites() {
        while let packet = writeQueue.first, isOpen {
            var written = 0
            packet.withUnsafeBytes { _ = SSLWrite(context!, $0, packet.count, &written) }
            if written == packet.count {
                _ = writeQueue.removeFirst()
            } else {
                if written > 0 {
                    writeQueue[0] = packet.subdata(in: written ..< packet.count)
                }
                break
            }
        }
    }
}
