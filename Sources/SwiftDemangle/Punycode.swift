import Foundation

/// Swift's Punycode dialect uses `_` as the delimiter and `A...J` for digits 26...35.
enum Punycode {
	static func decodePunycodeUTF8(_ value: String) throws -> String {
		let input = Array(value.unicodeScalars)
		var output: [UnicodeScalar] = []
		var position = 0
		if let delimiterIndex = input.lastIndex(of: "_") {
			let basicScalars = input[..<delimiterIndex]
			guard basicScalars.allSatisfy({ $0.value <= 0x7F }) else {
				throw SwiftSymbolParseError.punycodeParseError
			}
			output.append(contentsOf: basicScalars)
			position = delimiterIndex + 1
		}

		let maximumInteger = Int(Int32.max)
		let base = 36
		let minimumThreshold = 1
		let maximumThreshold = 26
		var codePoint = 128
		var insertionIndex = 0
		var bias = 72
		while position < input.count {
			let previousIndex = insertionIndex
			var weight = 1
			var thresholdIndex = base
			while true {
				guard position < input.count else { throw SwiftSymbolParseError.punycodeParseError }
				let scalar = input[position]
				position += 1
				let digit: Int
				switch scalar {
				case "a"..."z": digit = Int(scalar.value - UnicodeScalar("a").value)
				case "A"..."J": digit = Int(scalar.value - UnicodeScalar("A").value) + 26
				default: throw SwiftSymbolParseError.punycodeParseError
				}
				guard digit <= (maximumInteger - insertionIndex) / weight else {
					throw SwiftSymbolParseError.punycodeParseError
				}
				insertionIndex += digit * weight
				let threshold = min(max(thresholdIndex - bias, minimumThreshold), maximumThreshold)
				if digit < threshold { break }
				guard weight <= maximumInteger / (base - threshold) else {
					throw SwiftSymbolParseError.punycodeParseError
				}
				weight *= base - threshold
				thresholdIndex += base
			}

			let outputCount = output.count + 1
			var delta = (insertionIndex - previousIndex) / (previousIndex == 0 ? 700 : 2)
			delta += delta / outputCount
			var adjustment = 0
			while delta > 455 {
				delta /= base - minimumThreshold
				adjustment += base
			}
			bias = adjustment + base * delta / (delta + 38)
			guard insertionIndex / outputCount <= maximumInteger - codePoint else {
				throw SwiftSymbolParseError.punycodeParseError
			}
			codePoint += insertionIndex / outputCount
			insertionIndex %= outputCount
			let scalarValue = (0xD800..<0xD880).contains(codePoint) ? codePoint - 0xD800 : codePoint
			guard let scalar = UnicodeScalar(scalarValue) else { throw SwiftSymbolParseError.punycodeParseError }
			output.insert(scalar, at: insertionIndex)
			insertionIndex += 1
		}
		return String(String.UnicodeScalarView(output))
	}
}
