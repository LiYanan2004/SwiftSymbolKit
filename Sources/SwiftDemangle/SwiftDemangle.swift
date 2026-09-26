//
//  SwiftDemangle.swift
//  SwiftDemangle
//
//  Created by Matt Gallagher on 2017/11/17.
//  Copyright © 2017 Matt Gallagher. All rights reserved.
//

import Foundation

// MARK: Public interface

extension SwiftSymbol {
	/// Parses a mangled Swift symbol or type into a symbol tree.
	///
	/// - Parameters:
	///   - mangledSymbol: The mangled symbol or type encoding.
	///   - isType: Whether to parse a type encoding without a symbol prefix. Defaults to `false`.
	/// - Throws: `SwiftSymbolParseError` when parsing fails.
	public init(_ mangledSymbol: String, isType: Bool = false) throws {
		try self.init(mangledSymbol.unicodeScalars, isType: isType)
	}

	/// Parses Unicode scalars containing a mangled Swift symbol or type.
	///
	/// - Parameters:
	///   - mangledSymbol: The mangled symbol or type encoding.
	///   - isType: Whether to parse a type encoding without a symbol prefix. Defaults to `false`.
	///   - symbolicReferenceResolver: Resolves a signed relative reference and the scalar offset
	///     of its four-byte payload. Binary payload bytes must be represented by scalars in
	///     `0...255`; the preceding scalar identifies the reference kind.
	/// - Throws: `SwiftSymbolParseError` when parsing fails, or an error from the resolver.
	public init<Scalars: Collection>(
		_ mangledSymbol: Scalars,
		isType: Bool = false,
		symbolicReferenceResolver: ((Int32, Int) throws -> SwiftSymbol)? = nil
	) throws where Scalars.Element == UnicodeScalar {
		var demangler = Demangler(scalars: mangledSymbol)
		demangler.symbolicReferenceResolver = symbolicReferenceResolver
		if isType {
			self = try demangler.demangleType()
			return
		}
		let mangledName = String(String.UnicodeScalarView(mangledSymbol))
		let isModernSymbol = getManglingPrefixLength(mangledSymbol) != 0 || mangledName.hasPrefix("async_Main") || mangledName.hasPrefix("_async_Main")
		self = try isModernSymbol ? demangler.demangleSymbol() : demangler.demangleSwift3TopLevelSymbol()
		originalMangling = mangledName
	}
}

extension SwiftSymbol {
	/// Demangles a symbol, returning the original name when parsing fails.
	///
    /// Classification, when requested, also applies to names that cannot be parsed.
	public static func demangle(_ mangled: String, using options: SymbolPrintOptions = .default) -> String {
		guard let symbol = try? SwiftSymbol(mangled) else {
			let prefix = options.contains(.classify) ? SwiftSymbol.classificationPrefix(for: mangled, symbol: nil) : ""
			return prefix + mangled
		}
		let printed = symbol.print(using: options)
		return printed.isEmpty ? mangled : printed
	}
}

extension SwiftSymbol: CustomStringConvertible {
	/// Overridden method to allow simple printing with default options
	public var description: String {
		var printer = SymbolPrinter()
		_ = printer.printName(self)
		return printer.target
	}
	
	/// Prints `SwiftSymbol`s to a String with the full set of printing options.
	///
	/// - Parameter options: an option set containing the different `DemangleOptions` from the Swift project.
	/// - Returns: `self` printed to a string according to the specified options.
	public func print(using options: SymbolPrintOptions = .default) -> String {
		var printer = SymbolPrinter(options: options)
		_ = printer.printName(self)
		if options.contains(.classify), let originalMangling {
			return Self.classificationPrefix(for: originalMangling, symbol: self) + printer.target
		}
		return printer.target
	}
}

private extension SwiftSymbol {
	static func classificationPrefix(for mangledName: String, symbol: SwiftSymbol?) -> String {
		var classifications: [String] = []
		if !mangledName.hasPrefix("async_Main") && !mangledName.hasPrefix("_async_Main") && !mangledName.hasPrefix("_T") && getManglingPrefixLength(mangledName.unicodeScalars) == 0 {
			classifications.append("N")
		}
		if isThunkSymbol(mangledName, symbol: symbol) {
			classifications.append("T:" + thunkTarget(mangledName))
		}
		if let symbol, symbol.kind != .global || symbol.children.first.map({ usesNonSwiftCallingConvention($0.kind) }) == true {
			classifications.append("C")
		}
		return classifications.isEmpty ? "" : "{" + classifications.joined(separator: ",") + "} "
	}

	static func usesNonSwiftCallingConvention(_ kind: Kind) -> Bool {
		switch kind {
		case .typeMetadataAccessFunction, .valueWitness, .protocolWitnessTableAccessor,
			.genericProtocolWitnessTableInstantiationFunction, .lazyProtocolWitnessTableAccessor,
			.associatedTypeMetadataAccessor, .associatedTypeWitnessTableAccessor,
			.baseWitnessTableAccessor, .objCAttribute:
			return true
		default:
			return false
		}
	}

	static func isThunkSymbol(_ mangledName: String, symbol: SwiftSymbol?) -> Bool {
		if getManglingPrefixLength(mangledName.unicodeScalars) != 0 {
			let name = Self.strippingAsyncContinuation(from: Self.strippingSuffix(from: mangledName))
			guard ["TA", "Ta", "To", "TO", "TR", "Tr", "TW", "fC"].contains(where: name.hasSuffix) else { return false }
			let parsedSymbol = name == mangledName ? symbol : try? SwiftSymbol(name)
			guard parsedSymbol?.kind == .global, let kind = parsedSymbol?.children.first?.kind else { return false }
			switch kind {
			case .objCAttribute, .nonObjCAttribute, .partialApplyObjCForwarder,
				.partialApplyForwarder, .reabstractionThunkHelper, .reabstractionThunk,
				.protocolWitness, .allocator:
				return true
			default:
				return false
			}
		}
		guard mangledName.hasPrefix("_T") else { return false }
		let remainder = mangledName.dropFirst(2)
		return ["To", "TO", "PA_", "PAo_"].contains(where: remainder.hasPrefix)
	}

	static func thunkTarget(_ mangledName: String) -> String {
		if getManglingPrefixLength(mangledName.unicodeScalars) != 0 {
			guard Self.strippingSuffix(from: mangledName) == mangledName else { return "" }
			let name = Self.strippingAsyncContinuation(from: mangledName)
			if ["TR", "Tr", "TW"].contains(where: name.hasSuffix) { return "" }
			if name.hasSuffix("fC") { return String(name.dropLast()) + "c" }
			return String(name.dropLast(2))
		}
		let remainder = mangledName.dropFirst(2)
		if remainder.hasPrefix("PAo_") { return String(remainder.dropFirst(4)) }
		if remainder.hasPrefix("PA_") { return String(remainder.dropFirst(3)) }
		return "_T" + remainder.dropFirst(2)
	}

	static func strippingSuffix(from mangledName: String) -> String {
		guard mangledName.last?.isNumber == true, let dot = mangledName.firstIndex(of: ".") else { return mangledName }
		return String(mangledName[..<dot])
	}

	static func strippingAsyncContinuation(from mangledName: String) -> String {
		guard mangledName.hasSuffix("_") else { return mangledName }
		var name = String(mangledName.dropLast())
		while name.last?.isNumber == true { name.removeLast() }
		if name.hasSuffix("TQ") || name.hasSuffix("TY") { return String(name.dropLast(2)) }
		return mangledName
	}
}
