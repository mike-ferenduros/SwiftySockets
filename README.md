# SwiftySockets
An incomplete, untested Swifty socket library

Socket6 and sockaddr_in6 are simple wrappers for a subset the socket API - they don't add functionality, but only hide the ghastliness of persuading Swift's strict type system to talk to an 80's-style C API. They also paper over some trivial but annoying differences between the Linux and Darwin socket APIs, and add convenience properties for some common socket options.

DispatchSocket wraps Socket6, sending you delegate notifications for readable / writable / disconnect events, and closes the socket on deinit.

StreamSocket wraps DispatchSocket, providing buffered, async reading and writing.

ListenSocket is what it sounds like.

SwiftySockets is nominally IPv6 only, but interoperating with IPv4 is as simple as wrapping an IPv4 address in an IPv6 one and letting your OS magically take care of it.

It generally tracks the Swift 3 snapshots on Linux, and the XCode betas on Mac and iOS.
