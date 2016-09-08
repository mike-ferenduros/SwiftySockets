# SwiftySockets
An early Swifty IPv6 socket library

SwiftySockets is nominally IPv6 only, but interoperating with IPv4 is as simple as wrapping an IPv4 address in an IPv6 one and letting your OS magically take care of it.

Socket6 and sockaddr_in6/in6_addr are simple wrappers for a subset the socket API - they don't add functionality, but only hide the ghastliness of persuading Swift's strict type system to talk to an 80's-style C API. They also paper over some trivial but annoying differences between the Linux and Darwin socket APIs, and add convenience properties for some common socket options.

DispatchSocket wraps Socket6, calling your handler blocks on readable or writableevents, and closing the socket on deinit. On Linux it's affected by a bug in the current Swift3 development snapshots that means you won't receive any writable events if you also register for readable events.

DispatchSocket also has some extension functions to listen for new connections.

Note that this is a pure socket-API based library, and to quote the iOS docs "In iOS, POSIX networking is discouraged because it does not activate the cellular radio or on-demand VPN."

SSL is not yet implemented, but coming soon, probably with separate implementations for Darwin (SecureTransport) and Linux (OpenSSL?).

## Simple TCP echo-server example using DispatchSocket:
```
import Dispatch
import SwiftySockets


var connections = Set<DispatchSocket>()

//Catch connections on port 1234, suppressing 'port already in use' errors
let listener = try DispatchSocket.listen(port: 1234, options: .reuseAddress) { socket in

	let dsock = DispatchSocket(socket: socket)

	print("Connected \(dsock)")

	dsock.onReadable = { available in
		//Readable but 0 bytes available means the TCP connection was closed at the other end
		guard available > 0 else {
			print("Disconnecting \(dsock)")
			try? dsock.close()
			connections.remove(dsock)
			return
		}

		//Receive all available data
		if let data = try? dsock.socket.recv() {
			print("Echoing \(data.count) bytes from \(dsock.socket.peername)")
			//DispatchSocket will queue the Data and send it in an onWritable handler.
			dsock.write(data)
		}
	}

	connections.insert(dsock)
}

print("Listening on \(listener.socket.sockname!.port)")

dispatchMain()
```
## Or just plain sockets + GCD
```
import Dispatch
import SwiftySockets


func handleConnection(socket: Socket6) {

	print("Connected \(socket)")

	DispatchQueue.global().async {

		while true {
			//Block until there's something to receive
			_ = try? socket.recv(length: 1, options: .peek)

			//Receive all buffered data
			guard let data = try? socket.recv(), data.count > 0 else {
				print("Disconnecting \(socket)")
				try? socket.close()
				return
			}

			print("Echoing \(data.count) bytes")
			_ = try? socket.send(buffer: data)
		}
	}
}



var listener = try Socket6(type: .stream)
listener.reuseAddress = true
listener.ip6Only = false
try listener.bind(to: sockaddr_in6.any(port: 1234))
try listener.listen()

print("Listening on \(listener)")

DispatchQueue.global().async {
	while true {
		if let socket = try? listener.accept() {
			handleConnection(socket: socket)
		}
	}
}

dispatchMain()
```
