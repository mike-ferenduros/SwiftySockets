# SwiftySockets
An early Swifty IPv6 socket library

SwiftySockets is nominally IPv6 only, but interoperating with IPv4 is as simple as wrapping an IPv4 address in an IPv6 one and letting your OS magically take care of it.

Socket6 and sockaddr_in6 are simple wrappers for a subset the socket API - they don't add functionality, but only hide the ghastliness of persuading Swift's strict type system to talk to an 80's-style C API. They also paper over some trivial but annoying differences between the Linux and Darwin socket APIs, and add convenience properties for some common socket options.

DispatchSocket wraps Socket6, sending you delegate notifications for readable / writable / disconnect events, and closing the socket on deinit. On Linux it's affected by a bug in the current Swift3 development snapshots that means you won't receive any writable events.

StreamSocket wraps DispatchSocket providing buffered, async reading and writing (and working around the above DispatchSocket Linux bug).

ListenSocket is what it sounds like.

Note that this is a pure socket-based library, and to quote the iOS docs "In iOS, POSIX networking is discouraged because it does not activate the cellular radio or on-demand VPN."

SSL is not yet implemented, but coming soon, probably with separate implementations for Darwin (SecureTransport) and Linux (OpenSSL?).
