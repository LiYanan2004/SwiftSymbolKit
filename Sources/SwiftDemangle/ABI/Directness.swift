//
//  Directness.swift
//  SwiftSymbolKit
//
//  Created by Yanan Li on 2026/9/29.
//

enum Directness: UInt64, CustomStringConvertible {
	case direct = 0
	case indirect = 1
	
	var description: String {
		switch self {
		case .direct: return "direct"
		case .indirect: return "indirect"
		}
	}
}
