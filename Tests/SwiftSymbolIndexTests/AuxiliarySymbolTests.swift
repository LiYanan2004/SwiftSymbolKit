import SwiftDemangle
import Testing
@testable import SwiftSymbolIndexStore

struct AuxiliarySymbolTests {
    @Test func retainsSpecificKindsWithoutSynthesizingDeclarations() async throws {
        for fixture in AuxiliarySymbolFixture.allCases {
            var store = SymbolIndexStore()
            try await store.merge(contentsOf: [fixture.input, String(fixture.input.dropFirst())])
            let record = try #require(store.symbolRecordsByMangledName.values.first)
            #expect(store.symbolRecordsByMangledName.count == 1)
            #expect(record.role == .auxiliary(fixture.expectedKind))
            #expect(record.demangledSymbol.children.first?.kind == fixture.expectedKind)
            #expect(record.mangledSymbols == [fixture.input, String(fixture.input.dropFirst())])
            #expect(record.declarationIDs.isEmpty)
            #expect(store.declarationsByID.isEmpty)
            #expect(store.conformances.isEmpty)
            #expect(store.runtimeSymbols.isEmpty)
            #expect(store.diagnostics.isEmpty)
            let output = try await SwiftInterfaceWriter(configuration: .init(moduleName: "Example", compilerVersion: "test")).write(store)
            #expect(output.diagnostics.isEmpty)
            #expect(!output.text.contains(fixture.input))
            #expect(!output.text.contains("Symbols without a recoverable source declaration"))
        }
    }

    @Test func rejectsMissingAuxiliaryChildren() {
        for fixture in AuxiliarySymbolFixture.allCases {
            #expect(throws: SymbolExtractor.ExtractionError.self) {
                try SymbolExtractor().extract(SwiftSymbol(kind: fixture.expectedKind), mangledSymbol: "invalid")
            }
        }
    }

    @Test func preservesKindsAndDeclarationsForExistingWrappers() throws {
        let function = try SwiftSymbol("$s7Example6chooseyySiF").children[0]
        for kind in [SwiftSymbol.Kind.dispatchThunk, .curryThunk] {
            let extraction = try SymbolExtractor().extract(SwiftSymbol(kind: kind, children: [function]), mangledSymbol: "wrapper")
            #expect(extraction.record.role == .auxiliary(kind))
            #expect(extraction.declarations.map(\.name) == ["choose"])
            #expect(extraction.diagnostics.isEmpty)
        }
        for kind in [SwiftSymbol.Kind.asyncFunctionPointer, .coroFunctionPointer, .objCAttribute] {
            let tree = SwiftSymbol(kind: .global, children: [SwiftSymbol(kind: kind), function])
            let extraction = try SymbolExtractor().extract(tree, mangledSymbol: "attribute")
            #expect(extraction.record.role == .auxiliary(kind))
            #expect(extraction.declarations.map(\.name) == ["choose"])
            #expect(extraction.diagnostics.isEmpty)
        }
    }
}
