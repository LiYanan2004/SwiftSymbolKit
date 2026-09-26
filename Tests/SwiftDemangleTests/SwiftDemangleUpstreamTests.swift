import Foundation
@testable import SwiftDemangle
import Testing

// swiftlang/swift, commit 7e8c70b0f7825128212f6dd1146c1f00b98d7a3f.
// Fixtures are copied from test/Demangle/Inputs, under Apache-2.0 with the Swift exception.
struct SwiftDemangleUpstreamTests {
    enum Corpus: String, CaseIterable {
        case standard = "upstream-manglings"
        case simplified = "upstream-simplified-manglings"
        case clangTypes = "upstream-clang-manglings"

        var options: SymbolPrintOptions {
            self == .simplified ? .simplified : .default.union(.synthesizeSugarOnTypes)
        }

        var expectedCount: Int {
            switch self {
            case .standard: 521
            case .simplified: 217
            case .clangTypes: 2
            }
        }
    }

    @Test(arguments: Corpus.allCases)
    func matchesUpstream(corpus: Corpus) throws {
        let url = try #require(Bundle.module.url(forResource: corpus.rawValue, withExtension: "txt", subdirectory: "Fixtures"))
        let contents = try String(contentsOf: url, encoding: .utf8)
        var count = 0
        for line in contents.components(separatedBy: .newlines) {
            let components = line.components(separatedBy: " ---> ")
            guard components.count == 2 else { continue }
            let input = components[0].trimmingCharacters(in: .whitespaces)
            let expected = components[1]
            // The upstream CLI only classifies text recognized as a symbol.
            let options = expected.hasPrefix("{") ? corpus.options.union(.classify) : corpus.options
            #expect(demangleSwiftSymbol(input, using: options) == expected, "\(input)")
            count += 1
        }
        #expect(count == corpus.expectedCount)
    }

    @Test func additionalParserBranches() throws {
        let examples: [(input: String, expected: String)] = [
            ("$sBj", "Builtin.Job"),
            ("$sBD", "Builtin.DefaultActorStorage"),
            ("$sBd", "Builtin.NonDefaultDistributedActorStorage"),
            ("$sBc", "Builtin.RawUnsafeContinuation"),
            ("$sBP", "Builtin.PackIndex"),
            ("$sBT", "Builtin.TheTupleType"),
            ("$s$2_SiBVD", "Builtin.FixedArray<3, Swift.Int>"),
            ("$sSiXSqD", "Swift.Int?"),
            ("$sSiXSaD", "[Swift.Int]"),
            ("$sSSSiXSDD", "[Swift.String : Swift.Int]"),
            ("$sSiXSpD", "(Swift.Int)"),
            ("$s2hi1SV1iSivb", "hi.S.i.borrow : Swift.Int"),
            ("$s2hi1SV1iSivz", "hi.S.i.mutate : Swift.Int"),
            ("$s2hi1SV1iSivaP", "hi.S.i.nativePinningMutableAddressor : Swift.Int"),
            ("$sSiMi", "type metadata instantiation function for Swift.Int"),
            ("$sSiIgzl_D", "@callee_guaranteed () -> (@error @guaranteed_address Swift.Int)"),
            ("$sSiIgzg_D", "@callee_guaranteed () -> (@error @guaranteed Swift.Int)"),
            ("$sSiIgzm_D", "@callee_guaranteed () -> (@error @inout Swift.Int)"),
            ("$sIOg_D", "@called(once) @callee_guaranteed () -> ()"),
            ("$s3fooySi_tcD", "(foo: Swift.Int) -> ()"),
            ("$s3fooySi_tYbcD", "@Sendable (foo: Swift.Int) -> ()"),
            ("$s4main3foo3BarfMq_", "preamble macro @Bar expansion #1 of foo in main"),
            ("$s4main3foo3BarfMe_", "extension macro @Bar expansion #1 of foo in main")
        ]
        for example in examples {
            #expect(try parseMangledSwiftSymbol(example.input).print() == example.expected, "\(example.input)")
        }
    }

    @Test func rejectsInvalidTypesAndNumbers() {
        for input in ["", "SS_", "SSIeAghrx_", "Bf_", "Bi_", "Bv_", "Bi2147483647_", "Bi18446744073709551615_"] {
            #expect(throws: (any Error).self) { try parseMangledSwiftSymbol(input, isType: true) }
        }
        #expect(demangleSwiftSymbol("$sTJSdSSSpSrSUSP") == "$sTJSdSSSpSrSUSP")
        #expect(demangleSwiftSymbol("$sTfr/") == "$sTfr/")
    }

    @Test func typeNodesAndNullTermination() throws {
        let borrow = try parseMangledSwiftSymbol("SiBW", isType: true)
        #expect(borrow.kind == .type)
        #expect(borrow.children.first?.kind == .builtinBorrow)
        let fixedArray = try parseMangledSwiftSymbol("$2_SiBV", isType: true)
        #expect(fixedArray.kind == .type)
        #expect(fixedArray.children.first?.kind == .builtinFixedArray)
        let function = try parseMangledSwiftSymbol("yySiXyc", isType: true)
        #expect(function.children.first?.children.first?.kind == .yieldTypes)
        let opaque = try parseMangledSwiftSymbol("QR0_", isType: true)
        #expect(opaque.children.first?.children.first?.kind == .opaqueReturnTypeIndex)
        #expect(opaque.children.first?.children.first?.index == 1)
        #expect(try parseMangledSwiftSymbol("Si\0ignored", isType: true).print() == "Swift.Int")
        #expect(getManglingPrefixLength("@__swiftmacro_".unicodeScalars) == 13)
    }

    @Test func symbolicReferences() throws {
        let input = "\u{FF}\u{1}\u{FE}\u{FF}\u{FF}\u{FF}"
        let resolved = SwiftSymbol(kind: .typeSymbolicReference, contents: .index(42))
        let symbol = try parseMangledSwiftSymbol(input.unicodeScalars, isType: true) { value, offset in
            #expect(value == -2)
            #expect(offset == 2)
            return resolved
        }
        #expect(symbol.kind == resolved.kind)
        #expect(symbol.index == 42)
        let substitution = try parseMangledSwiftSymbol(("$s" + input + "AA").unicodeScalars) { _, _ in resolved }
        #expect(substitution.children.count == 2)
        for invalid in ["\u{1}\0\0", "\u{3}\0\0\0\0", "\u{1}\u{100}\0\0\0"] {
            #expect(throws: (any Error).self) {
                try parseMangledSwiftSymbol(invalid.unicodeScalars, isType: true) { _, _ in resolved }
            }
        }
    }
}
