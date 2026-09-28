import SwiftIndexing
import Testing

struct IndexingSourceTests {
    @Test func parsesSymbolsWithoutAnIndexStore() async throws {
        let context = IndexingContext(moduleName: "Example", targetTriple: "arm64-apple-macosx", sdkIdentifier: "test")
        let source = MangledSymbolSource(exportedSymbols: ["_$s7Example3FooVMn"], context: context)
        let result = try await source.read()
        #expect(result.context == context)
        #expect(result.declarations.map(\.name) == ["Foo"])
        #expect(result.symbolRecords.first?.mangledSymbol == "_$s7Example3FooVMn")
        #expect(result.symbolRecords.first?.declarationIDs == Set(result.declarations.map(\.id)))
        #expect(result.exportedSymbols == ["_$s7Example3FooVMn"])
    }
}
