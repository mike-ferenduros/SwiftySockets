//
//  DispatchSocket+listen.swift
//  vrtest
//
//  Created by Michael Ferenduros on 27/08/2016.
//  Copyright © 2016 Mike Ferenduros. All rights reserved.
//

import Foundation


extension DispatchSocket {

    public struct ListenOptions : OptionSet {
        public init(rawValue: Int) { self.rawValue = rawValue }
        public let rawValue: Int
        
        ///SO_REUSEADDR: allow local address reuse
        public static let reuseAddress = ListenOptions(rawValue: 1<<0)

        ///IPV6_V6ONLY: only bind INET6 at wildcard bind
        public static let ip6Only      = ListenOptions(rawValue: 1<<1)
    }

    public func listen(handler: @escaping (Socket6)->()) throws {
        guard isOpen else { return }
        guard self.onReadable == nil else { return /* FIXME: throw */ }

        self.onReadable = { [weak self] _ in
            if self?.isOpen == true, let newsock = try? self!.socket.accept() {
                handler(newsock)
            }
        }
        try self.socket.listen()
    }

    public static func listen(address: sockaddr_in6, options: ListenOptions = [], handler: @escaping (Socket6)->()) throws -> DispatchSocket {
        var s = try Socket6(type: .stream)
        s.reuseAddress = options.contains(.reuseAddress)
        s.ip6Only = options.contains(.ip6Only)
        try s.bind(to: address)

        let dsock = DispatchSocket(socket: s)
        try dsock.listen(handler: handler)
        return dsock
    }

    public static func listen(port: UInt16, options: ListenOptions = [], handler: @escaping (Socket6)->()) throws -> DispatchSocket {
        return try listen(address: sockaddr_in6.any(port: port), options: options, handler: handler)
    }

    public static func listen(options: ListenOptions = [], handler: @escaping (Socket6)->()) throws -> DispatchSocket {
        return try listen(address: sockaddr_in6.any(), options: options, handler: handler)
    }



    public static func connect(to address: sockaddr_in6, completion: @escaping (Result<Socket6,Error>)->()) {
        do {
            let sock = try Socket6(type: .stream)

            DispatchQueue.global().async {
                do {
                    try sock.connect(to: address)
                    DispatchQueue.main.async {
                        completion(.success(sock))
                    }
                } catch let err {
                    DispatchQueue.main.async {
                        try? sock.close()
                        completion(.failure(err))
                    }
                }
            }
        }  catch let err { completion(.failure(err)) }
    }


    ///Connect to all passed addresses in parallel, calling completion-handler with the first successful connection, or with all returned errors
    public static func connect(to addresses: [sockaddr_in6], completion: @escaping (Result<Socket6,[Error]>)->()) {
        var errors = [Error?](repeating: nil, count: addresses.count)
        var pending = addresses.count
        for i in 0 ..< addresses.count {

            connect(to: addresses[i]) { result in
                guard pending > 0 else { return }
                switch result {
                    case .success(let socket):
                        completion(.success(socket))
                        pending = 0
                    case .failure(let error):
                        errors[i] = error
                        pending -= 1
                        if pending == 0 {
                            completion(.failure(errors.flatMap { $0 }))
                        }
                }
            }
        }
    }
}
