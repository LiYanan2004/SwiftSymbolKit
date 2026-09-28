import SwiftIndexing
import SwiftSymbolIndexStore
import Testing

struct ContextIngestionTests {
    private let device = IndexingTarget(architecture: .arm64, platform: .iOS)
    private let authenticatedDevice = IndexingTarget(architecture: .arm64e, platform: .iOS)
    private let symbol = "$s7Example3FooVMn"

    @Test func primaryEstablishesContextAndRetainsPerSymbolTargetsAcrossBatches() async throws {
        let context = IndexingContext(moduleName: "Example", targets: [device, authenticatedDevice])
        var index = SymbolIndexStore()
        #expect(index.context == nil)
        try await index.ingest(MangledSymbolSource(exportedSymbols: [symbol], context: context,
            exportedSymbolTargets: [symbol: [device]]))
        try await index.ingest(MangledSymbolSource(exportedSymbols: ["_" + symbol], context: context,
            exportedSymbolTargets: ["_" + symbol: [authenticatedDevice]]))
        #expect(index.context == context)
        #expect(index.exportedSymbolTargets[symbol] == context.targets)
        #expect(index.exportedSymbols == [symbol])
        #expect(index.sources.count == 1)
    }

    @Test func rejectsASecondPrimaryArtifactWithoutMutation() async throws {
        let context = IndexingContext(moduleName: "Example", targets: [device])
        var index = SymbolIndexStore()
        try await index.ingest(MangledSymbolSource(exportedSymbols: [symbol], context: context))
        let primarySource = index.primarySource
        let other = SymbolEvidenceSource(kind: .mangledSymbols, location: "Other.tbd",
            artifactIdentifier: "other", lineageIdentifier: "other")
        do {
            try await index.ingest(MangledSymbolSource(exportedSymbols: [symbol], context: context, source: other))
            Issue.record("Expected a different primary artifact to be rejected")
        } catch SymbolIndexStore.IngestionError.differentPrimarySource {
            #expect(index.primarySource == primarySource)
            #expect(index.sources.count == 1)
            #expect(index.exportedSymbolTargets == [symbol: [device]])
        }
    }

    @Test func supplementalContextIsReadFromItsResultBeforeAnyMutation() async throws {
        let context = IndexingContext(moduleName: "Example", targets: [device])
        var index = SymbolIndexStore()
        try await index.ingest(MangledSymbolSource(exportedSymbols: [symbol], context: context))
        let source = FixtureSource(result: IndexingResult(
            source: .init(kind: .swiftInterface, location: "Other.swiftinterface",
                artifactIdentifier: "other", lineageIdentifier: "other"),
            context: .init(moduleName: "Other", targets: [device])))
        do {
            try await index.ingest(source)
            Issue.record("Expected incompatible artifact metadata to be rejected")
        } catch SymbolIndexStore.IngestionError.incompatibleContext {
            #expect(index.context == context)
            #expect(index.sources.count == 1)
            #expect(index.exportedSymbols == [symbol])
            #expect(index.reconciliationIssues.isEmpty)
        }
    }

    @Test func supplementalSourceCannotEstablishThePrimary() throws {
        var index = SymbolIndexStore()
        let result = IndexingResult(source: .init(kind: .swiftInterface, location: "Example.swiftinterface",
            artifactIdentifier: "interface", lineageIdentifier: "interface"),
            context: .init(moduleName: "Example", targets: [device]))
        #expect(throws: SymbolIndexStore.IngestionError.primarySourceRequired) { try index.merge(result) }
        #expect(index.context == nil)
        #expect(index.sources.isEmpty)
    }

    @Test func malformedSymbolCoverageLeavesIndexEmpty() throws {
        var index = SymbolIndexStore()
        let result = IndexingResult(source: .init(kind: .mangledSymbols, location: "Example.tbd",
            artifactIdentifier: "tbd", lineageIdentifier: "tbd"),
            context: .init(moduleName: "Example", targets: [device]),
            exportedSymbols: [symbol], exportedSymbolTargets: [symbol: [authenticatedDevice]])
        #expect(throws: SymbolIndexStore.IngestionError.invalidExportEvidence) { try index.merge(result) }
        #expect(index.context == nil)
        #expect(index.primarySource == nil)
        #expect(index.exportedSymbols.isEmpty)
    }

    private struct FixtureSource: IndexingSource {
        let result: IndexingResult
        func read() async throws -> IndexingResult { result }
    }
}
