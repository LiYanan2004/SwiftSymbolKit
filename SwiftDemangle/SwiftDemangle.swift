//
//  SwiftDemangle.swift
//  SwiftDemangle
//
//  Created by Matt Gallagher on 2017/11/17.
//  Copyright © 2017 Matt Gallagher. All rights reserved.
//

import Foundation

// MARK: Public interface

/// This is likely to be the primary entry point to this file. Pass a string containing a Swift mangled symbol or type, get a parsed SwiftSymbol structure which can then be directly examined or printed.
///
/// - Parameters:
///   - mangled: the string to be parsed ("isType` is false, the string should start with a Swift Symbol prefix, _T, _$S or $S).
///   - isType: if true, no prefix is parsed and, on completion, the first item on the parse stack is returned.
/// - Returns: the successfully parsed result
/// - Throws: a SwiftSymbolParseError error that contains parse position when the error occurred.
public func parseMangledSwiftSymbol(_ mangled: String, isType: Bool = false) throws -> SwiftSymbol {
	return try parseMangledSwiftSymbol(mangled.unicodeScalars, isType: isType)
}

/// Pass a collection of `UnicodeScalars` containing a Swift mangled symbol or type, get a parsed SwiftSymbol structure which can then be directly examined or printed.
///
/// - Parameters:
///   - mangled: the collection of `UnicodeScalars` to be parsed ("isType` is false, the string should start with a Swift Symbol prefix, _T, _$S or $S).
///   - isType: if true, no prefix is parsed and, on completion, the first item on the parse stack is returned.
/// - Returns: the successfully parsed result
/// - Throws: a SwiftSymbolParseError error that contains parse position when the error occurred.
public func parseMangledSwiftSymbol<C: Collection>(_ mangled: C, isType: Bool = false, symbolicReferenceResolver: ((Int32, Int) throws -> SwiftSymbol)? = nil) throws -> SwiftSymbol where C.Iterator.Element == UnicodeScalar {
	var demangler = Demangler(scalars: mangled)
	demangler.symbolicReferenceResolver = symbolicReferenceResolver
	if isType {
		return try demangler.demangleType()
	} else if getManglingPrefixLength(mangled) != 0 {
		return try demangler.demangleSymbol()
	} else {
		return try demangler.demangleSwift3TopLevelSymbol()
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
		return printer.target
	}
}
