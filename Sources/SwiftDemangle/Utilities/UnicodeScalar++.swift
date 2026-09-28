//
//  UnicodeScalar++.swift
//  SwiftSymbolKit
//
//  Created by Yanan Li on 2026/9/29.
//

import Foundation

extension UnicodeScalar {
	/// Tests if the scalar is within a range
	func isInRange(_ range: ClosedRange<UnicodeScalar>) -> Bool {
		return range.contains(self)
	}
	
	/// Tests if the scalar is a plain ASCII digit
	var isDigit: Bool {
		return ("0"..."9").contains(self)
	}
	
	/// Tests if the scalar is a plain ASCII English alphabet lowercase letter
	var isLower: Bool {
		return ("a"..."z").contains(self)
	}
	
	/// Tests if the scalar is a plain ASCII English alphabet uppercase letter
	var isUpper: Bool {
		return ("A"..."Z").contains(self)
	}
	
	/// Tests if the scalar is a plain ASCII English alphabet letter
	var isLetter: Bool {
		return isLower || isUpper
	}
}
