@_spi(Testing) import SwiftSymbolIndexStore
import SwiftIndexing
import Testing

struct SymbolSourceTests {
    private static let context = IndexingContext(moduleName: "Example", targets: [.init(architecture: .arm64, platform: .macOS)])
    private static let symbols = ["_$s7Example3FooVMn", "$s7Example3FooV8computedSivg"]

    @Test func parsedIndexingResultAndConvenienceInputProduceTheSameInterface() async throws {
        var expectedIndex = SymbolIndexStore()
        try await expectedIndex.merge(contentsOf: Self.symbols)
        let source = MangledSymbolSource(exportedSymbols: Self.symbols, context: Self.context)
        var actualIndex = SymbolIndexStore()
        try actualIndex.merge(try await source.read())

        let writer = SwiftInterfaceWriter(configuration: .init(moduleName: "Example", compilerVersion: "test"))
        let expected = try await writer.write(expectedIndex)
        let actual = try await writer.write(actualIndex)
        #expect(actual.text == expected.text)
        #expect(actualIndex.exportedSymbols == ["$s7Example3FooVMn", "$s7Example3FooV8computedSivg"])
        #expect(actualIndex.sources == [source.source])
    }

    @Test func additionalExportsRemainInTheSingleStore() async throws {
        var index = SymbolIndexStore()
        try await index.ingest(MangledSymbolSource(exportedSymbols: [Self.symbols[0]], context: Self.context))
        try await index.ingest(MangledSymbolSource(exportedSymbols: [Self.symbols[1]], context: Self.context))
        #expect(index.declarationsByID.values.contains { $0.name == "computed" })
        let writer = SwiftInterfaceWriter(configuration: .init(moduleName: "Example", compilerVersion: "test"))
        let output = try await writer.write(index)
        #expect(output.text.contains("var computed: Swift.Int"))
    }

    @Test func sourcePreservesContextAndProvenanceInIndexingResult() async throws {
        let context = IndexingContext(
            moduleName: "Example",
            targets: [.init(architecture: .arm64, platform: .macOS)],
            sdkIdentifier: "sdk-a"
        )
        let provenance = SymbolEvidenceSource(kind: .mangledSymbols, location: "Example.tbd",
            artifactIdentifier: "tbd-digest", lineageIdentifier: "sdk-a-Example")
        let source = MangledSymbolSource(exportedSymbols: Self.symbols, context: context, source: provenance)
        let indexingResult = try await source.read()
        #expect(indexingResult.context == context)
        #expect(indexingResult.source == provenance)
        #expect(Set(indexingResult.symbolRecords.map(\.mangledSymbol)) == Set(Self.symbols))
        var index = SymbolIndexStore()
        try index.merge(indexingResult)
        #expect(index.sources == [provenance])
        #expect(index.declarationsByID.keys.allSatisfy { index.sourcesByDeclarationID[$0] == [provenance] })
    }

    @Test func incompatibleSourceLeavesIndexUnchanged() async throws {
        let context = IndexingContext(moduleName: "Example", targets: [.init(architecture: .arm64, platform: .macOS)], sdkIdentifier: "sdk-a")
        var index = SymbolIndexStore()
        try await index.ingest(MangledSymbolSource(exportedSymbols: [Self.symbols[0]], context: context))
        let identifiers = Set(index.declarationsByID.keys)
        let sources = index.sources
        let source = MangledSymbolSource(exportedSymbols: Self.symbols, context: .init(
            moduleName: context.moduleName, targets: context.targets, sdkIdentifier: "sdk-b"))
        do {
            try await index.ingest(source)
            Issue.record("Expected a context mismatch")
        } catch SymbolIndexStore.IngestionError.incompatibleContext {
            #expect(Set(index.declarationsByID.keys) == identifiers)
            #expect(index.sources == sources)
        }
    }

    @Test func failedSourceReadLeavesExistingIndexIntact() async throws {
        var index = SymbolIndexStore()
        try await index.ingest(MangledSymbolSource(exportedSymbols: [Self.symbols[0]], context: Self.context))
        let identifiers = Set(index.declarationsByID.keys)
        let source = MangledSymbolSource(exportedSymbols: [Self.symbols[1], "invalid"], context: Self.context)
        do {
            try await index.ingest(source)
            Issue.record("Expected invalid symbol parsing to fail")
        } catch {
            #expect(Set(index.declarationsByID.keys) == identifiers)
            #expect(index.symbolRecordsByMangledName[Self.symbols[1]] == nil)
        }
    }
}
