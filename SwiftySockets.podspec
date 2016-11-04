Pod::Spec.new do |s|
  s.name             = 'SwiftySockets'
  s.version          = '0.3.7'
  s.summary          = 'An early, Swifty socket wrapper library'

  s.description      = <<-DESC
SwiftySockets is nominally IPv6 only, but interoperating with IPv4 is as simple as wrapping an IPv4 address in an IPv6 one and letting your OS magically take care of it.
Socket6 and sockaddr_in6/in6_addr are simple wrappers for a subset the socket API - they don't add functionality, but only hide the ghastliness of persuading Swift's strict type system to talk to an 80's-style C API. They also paper over some trivial but annoying differences between the Linux and Darwin socket APIs, and add convenience properties for some common socket options.
DispatchSocket wraps Socket6, calling your delegates on readable or writable events and closing the socket on deinit. It also hacks around a Linux/corelibs bug that would otherwise prevent you from getting both readable and writable events.
ListenSocket is a simple DispatchSocket subclass that listens for TCP connections and hands off the new sockets via a callback.
BufferedSocket subclasses DispatchSocket to provide easy asynchronous reading and writing.
Note that this is a pure socket-API based library, and to quote the iOS docs "In iOS, POSIX networking is discouraged because it does not activate the cellular radio or on-demand VPN."
SSL is not yet implemented, but coming soon, probably with separate implementations for Darwin (SecureTransport) and Linux (OpenSSL?).
                       DESC

  s.homepage         = 'https://github.com/mike-ferenduros/SwiftySockets'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Mike Ferenduros' => 'mike.ferenduros@gmail.com' }
  s.source           = { :git => 'https://github.com/mike-ferenduros/SwiftySockets.git', :tag => s.version.to_s }
  # s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'

  s.ios.deployment_target = '8.0'

  s.source_files = 'Sources/*'

  s.pod_target_xcconfig = { 'SWIFT_VERSION' => '3.0' }

end
