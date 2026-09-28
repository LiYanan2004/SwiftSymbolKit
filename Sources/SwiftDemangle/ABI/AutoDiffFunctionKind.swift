//
//  AutoDiffFunctionKind.swift
//  SwiftSymbolKit
//
//  Created by Yanan Li on 2026/9/29.
//

enum AutoDiffFunctionKind: UnicodeScalar {
	case forward = "f"
	case reverse = "r"
	case differential = "d"
	case pullback = "p"
	
	init?(_ uint64: UInt64) {
		guard let uint32 = UInt32(exactly: uint64), let scalar = UnicodeScalar(uint32), let value = AutoDiffFunctionKind(rawValue: scalar) else { return nil }
		self = value
	}
}
