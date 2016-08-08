//
//  POSIXError.swift
//  SwiftySockets
//
//  Created by Michael Ferenduros on 08/08/2016.
//  Copyright © 2016 Mike Ferenduros. All rights reserved.
//

import Foundation


enum POSIXError : Int32, Error, CustomStringConvertible {

    var description: String {
        return String(cString: strerror(rawValue))
    }

	case perm			= 1
	case noent			= 2
	case srch			= 3
	case intr			= 4
	case io         	= 5
	case nxio			= 6
	case toobig			= 7
	case noexec			= 8
	case badf			= 9
	case child			= 10
	case deadlk			= 11
	case nomem			= 12
	case acces			= 13
	case fault			= 14
	case notblk			= 15
	case busy			= 16
	case exist			= 17
	case xdev			= 18
	case nodev			= 19
	case notdir			= 20
	case isdir			= 21
	case inval			= 22
	case nfile			= 23
	case mfile			= 24
	case notty			= 25
	case txtbsy			= 26
	case fbig			= 27
	case nospc			= 28
	case spipe			= 29
	case rofs			= 30
	case mlink			= 31
	case pipe			= 32
	case dom			= 33
	case range			= 34
	case again			= 35
	case inprogress		= 36
	case already		= 37
	case notsock		= 38
	case destaddrreq	= 39
	case msgsize		= 40
	case prototype		= 41
	case noprotoopt		= 42
	case protonosupport	= 43
	case socktnosupport	= 44
	case notsup			= 45
	case pfnosupport	= 46
	case afnosupport	= 47
	case addrinuse		= 48
	case addrnotavail	= 49
	case netdown		= 50
	case netunreach		= 51
	case netreset		= 52
	case connaborted	= 53
	case connreset		= 54
	case nobufs			= 55
	case isconn			= 56
	case notconn		= 57
	case shutdown		= 58
	case toomanyrefs	= 59
	case timedout		= 60
	case connrefused	= 61
	case loop			= 62
	case nametoolong	= 63
	case hostdown		= 64
	case hostunreach	= 65
	case notempty		= 66
	case proclim		= 67
	case users			= 68
	case dquot			= 69
	case stale			= 70
	case remote			= 71
	case badrpc			= 72
	case rpcmismatch	= 73
	case progunavail	= 74
	case progmismatch	= 75
	case procunavail	= 76
	case nolck			= 77
	case nosys			= 78
	case ftype			= 79
	case auth			= 80
	case needauth		= 81
	case pwroff			= 82
	case deverr			= 83
	case overflow		= 84
	case badexec		= 85
	case badarch		= 86
	case shlibvers		= 87
	case badmacho		= 88
	case canceled		= 89
	case idrm			= 90
	case nomsg			= 91
	case ilseq			= 92
	case noattr			= 93
	case badmsg			= 94
	case multihop		= 95
	case nodata			= 96
	case nolink			= 97
	case nosr			= 98
	case nostr			= 99
	case proto			= 100
	case time			= 101
	case opnotsupp		= 102
	case nopolicy		= 103

    case unknown        = 99999
}
