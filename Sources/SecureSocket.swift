//
//  SecureSocket.swift
//  SwiftySockets
//
//  Created by Michael Ferenduros on 12/09/2016.
//  Copyright © 2016 Mike Ferenduros. All rights reserved.
//

import Foundation

public enum SecureSocketError : LocalizedError {
    case unknown, invalidCert, expiredCert
    var localizedDescription: String {
        switch self {
            case .unknown:          return "Unknown error"
            case .invalidCert:      return "Invalid certificate"
            case .expiredCert:      return "Expired certificate"
        }
    }
}

public protocol SecureSocketCertificate {
    ///Initialize from PEM-encoded signing key and certificates
    init?(key: Data, certs: [Data])
}

public protocol SecureSocketDelegate : class {
    ///Invoked when the socket handshake succeeds. Generally can be ignored
    func secureSocketHandshakeDidSucceed(_ socket: SecureSocket)

    ///Invoked when the socket handshake fails
    func secureSocketHandshakeDidFail(_ socket: SecureSocket, with: SecureSocketError)

    ///Invoked when the socket is disconnected after a successful handshake, but not when close() is called.
    func secureSocketDidDisconnect(_ socket: SecureSocket)
}

public enum SecureSocketSide { case client, server }

/**
    Interface for SSL/TLS enabled socket.

    Actual implementations are platform-specific and come with baggage, and hence live in separate modules
*/
public protocol SecureSocket : class {

    init(socket: Socket6, side: SecureSocketSide, certificate: SecureSocketCertificate?)

    weak var delegate: SecureSocketDelegate? { get set }

    ///May be nil, if certificates not supported (eg. iOS :( )
    static var CertificateType: SecureSocketCertificate.Type? { get }

    var isOpen: Bool { get }

    func close() throws

    /**
    Read exactly `count` bytes.
    - Parameter count: Number of bytes to read
    - Parameter completion: Completion-handler, invoked on DispatchQueue.main on success
    */
    func read(_ count: Int, completion: @escaping (Data)->())

    /**
    Read up to `max` bytes
    - Parameter max: Maximum number of bytes to read
    - Parameter completion: Completion-handler, invoked on DispatchQueue.main on success
    */
    func read(max: Int, completion: @escaping (Data)->())

    /**
    Read at least `min` bytes, up to `max` bytes
    - Parameter min: Minimum number of bytes to read
    - Parameter min: Maximum number of bytes to read
    - Parameter completion: Completion-handler, invoked on DispatchQueue.main on success
    */
    func read(min: Int, max: Int, completion: @escaping (Data)->())

    /**
    Asynchronously write data.
     - Parameter data: Data to be written.
    */
    func write(_ data: Data)
}

extension SecureSocket {
    public func read(_ count: Int, completion: @escaping (Data)->()) {
        read(min: count, max: count, completion: completion)
    }

    public func read(max: Int, completion: @escaping (Data)->()) {
        read(min: 1, max: max, completion: completion)
    }
}
