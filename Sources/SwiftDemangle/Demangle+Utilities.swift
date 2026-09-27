/// Utilities shared by demangling and node printing, corresponding to swift::Demangle.
enum Demangle {
	static func genericParameterName(depth: UInt64, index: UInt64) -> String {
		var name = ""
		var index = index
		repeat {
			name.unicodeScalars.append(UnicodeScalar(UnicodeScalar("A").value + UInt32(index % 26))!)
			index /= 26
		} while index != 0
		if depth != 0 {
			name += String(depth)
		}
		return name
	}

	static func getManglingPrefixLength<C: Collection>(_ scalars: C) -> Int where C.Iterator.Element == UnicodeScalar {
		var scanner = ScalarScanner(scalars: scalars)
		if scanner.conditional(string: "_T0") || scanner.conditional(string: "_$S") || scanner.conditional(string: "_$s") || scanner.conditional(string: "_$e") {
			return 3
		} else if scanner.conditional(string: "$S") || scanner.conditional(string: "$s") || scanner.conditional(string: "$e") {
			return 2
		} else if scanner.conditional(string: "@__swiftmacro_") {
			return 13
		}

		return 0
	}
}
