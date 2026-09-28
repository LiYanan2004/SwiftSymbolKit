//
//  MangledDifferentiabilityKind.swift
//  SwiftSymbolKit
//
//  Created by Yanan Li on 2026/9/29.
//

enum MangledDifferentiabilityKind: UnicodeScalar {
	case nonDifferentiable = "\0"
	case normal = "d"
	case linear = "l"
	case forward = "f"
	case reverse = "r"
	
	init?(_ uint64: UInt64) {
		guard let uint32 = UInt32(exactly: uint64), let scalar = UnicodeScalar(uint32), let value = MangledDifferentiabilityKind(rawValue: scalar) else { return nil }
		self = value
	}
}
