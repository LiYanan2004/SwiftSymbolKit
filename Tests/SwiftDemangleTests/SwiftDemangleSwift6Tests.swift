@testable import SwiftDemangle
import Testing

struct SwiftDemangleSwift6Tests {
	private let options = SymbolPrintOptions.default.union(.synthesizeSugarOnTypes)

	private func contains(_ kind: SwiftSymbol.Kind, in symbol: SwiftSymbol) -> Bool {
		return symbol.kind == kind || symbol.children.contains { contains(kind, in: $0) }
	}

	@Test func testSwiftSixTwoManglings() throws {
		let examples: [(mangled: String, demangled: String)] = [
			("$sBAD", "Builtin.ImplicitActor"),
			("$s5thing1PP1sAA1SVvxTwc", "coro function pointer to thing.P.s.yielding_mutate : thing.S"),
			("$s7Library1BC1iSivxTwd", "default override of Library.B.i.yielding_mutate : Swift.Int"),
			("$s7Library1BC1iSivxTwdTwc", "coro function pointer to default override of Library.B.i.yielding_mutate : Swift.Int"),
			("$s3use1xAA3OfPVy3lib1GVyAA1fQryFQOyQo_GAjE1PAAxAeKHD1_AIHO_HCg_Gvp", "use.x : use.OfP<lib.G<<<opaque return type of use.f() -> some>>.0>>"),
			("_T0SqWOB", "outlined init with take of Swift.Optional"),
			("_T0SqWOb", "outlined init with take of Swift.Optional"),
			("$s3red7MyActorC3runyxxyYaKYCXEYaKlFZ", "static red.MyActor.run<A>(nonisolated(nonsending) () async throws -> A) async throws -> A"),
			("$s$2_SiXSA_s11InlineArrayVy$2_SiGtD", "([3 of Swift.Int], Swift.InlineArray<3, Swift.Int>)"),
			("$s$2_$0_SSXSAXSA_s11InlineArrayVy$2_ABy$0_SSGGtD", "([3 of [1 of Swift.String]], Swift.InlineArray<3, Swift.InlineArray<1, Swift.String>>)")
		]
		for example in examples {
			let result = try SwiftSymbol(example.mangled).print(using: options)
			#expect(result == example.demangled, "\(example.mangled)")
		}
	}

	@Test func testEmbeddedSwiftPrefix() throws {
		for mangled in ["$eBAD", "_$eBAD"] {
			#expect(try SwiftSymbol(mangled).print(using: options) == "Builtin.ImplicitActor")
		}
	}

	@Test func testConstValueAnnotation() throws {
		let symbol = try SwiftSymbol("SiYg", isType: true)
		#expect(symbol.print(using: options) == "@const Swift.Int")
		#expect(symbol.children.first?.kind == .constValue)
		let literal = try SwiftSymbol("SiYt", isType: true)
		#expect(literal.print(using: options) == "_const Swift.Int")
		#expect(literal.children.first?.kind == .compileTimeLiteral)
	}

	@Test func testSILParameterMarkers() throws {
		let symbol = try SwiftSymbol("BAIgHgIL_", isType: true)
		#expect(symbol.print(using: options) == "@callee_guaranteed @async (@guaranteed Builtin.ImplicitActor) -> ()")
		#expect(contains(.implParameterIsolated, in: symbol))
		#expect(contains(.implParameterImplicitLeading, in: symbol))
	}

	@Test func testDependentOpaqueConformance() throws {
		let symbol = try SwiftSymbol("$s3use1xAA3OfPVy3lib1GVyAA1fQryFQOyQo_GAjE1PAAxAeKHD1_AIHO_HCg_Gvp")
		#expect(contains(.dependentProtocolConformanceOpaque, in: symbol))
	}

	@Test func testKeyPathMethodThunks() throws {
		let cases: [(String, String)] = [
			("$s18keypaths_inlinable13KeypathStructV8computedSSvpACTKmuq", "key path unapplied method for keypaths_inlinable.KeypathStruct.computed : Swift.String : keypaths_inlinable.KeypathStruct, serialized"),
			("$s18keypaths_inlinable13KeypathStructV8computedSSvpACTKMAq", "key path applied method for keypaths_inlinable.KeypathStruct.computed : Swift.String : keypaths_inlinable.KeypathStruct, serialized")
		]
		for (mangled, expected) in cases {
			#expect(try SwiftSymbol(mangled).print(using: options) == expected, "\(mangled)")
		}
	}

	@Test func testSimplifiedReabstractionThunks() throws {
		let cases: [(mangled: String, demangled: String)] = [
			("_TTRXFo_dSc_dSb_XFo_iSc_iSb_", "thunk for @callee_owned (@in UnicodeScalar) -> (@out Bool)"),
			("_TTRGrXFo_iV18switch_abstraction1A_ix_XFo_dS0__ix_", "thunk for @callee_owned (@unowned A) -> (@out A)")
		]
		for example in cases {
			#expect(try SwiftSymbol(example.mangled).print(using: .simplified) == example.demangled, "\(example.mangled)")
		}
	}
}
