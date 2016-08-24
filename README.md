# SwiftySockets
An incomplete, untested Swifty socket library

Socket6 and sockaddr_in6 are simple wrappers for a subset the socket API - they don't add functionality, but only hide the ghastliness of persuading Swift's strict type system to talk to an 80's-style C API. It also papers over some trivial but annoying differences between the Linux and Darwin socket APIs.

StreamSocket and DatagramSocket are higher-level classes for doing asynchronous reading and writing on TCP and UDP sockets respectively.

SwiftySockets is IPv6 only. That isn't quite as dumb as it seems, as your OS will bridge to and from IPv4 networks automagically.

It generally tracks the Swift 3 snapshots on Linux, and the XCode betas on Mac and iOS.

At this point, just read the code, it's fairly self-explanatory.
