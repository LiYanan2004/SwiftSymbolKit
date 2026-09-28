import Foundation
import SwiftSymbolIndexStore
import SwiftIndexing
import Testing

struct SourceSelectionTests {
    private static let context = IndexingContext(moduleName: "Example", targetTriple: "arm64-apple-macosx", sdkIdentifier: "test")
    @Test func selectsSourcesAndExportsThroughIndexStore() async throws {
        var index = SymbolIndexStore()
        try await index.ingest(sources: [
            .mangledSymbols(["_$s7Example3FooVMn"], context: Self.context),
            .mangledSymbols(["$s7Example3FooV8computedSivg"], context: Self.context),
        ])
        #expect(index.declarationsByID.values.contains { $0.name == "computed" })
        let writer = SwiftInterfaceWriter(configuration: .init(moduleName: "Example", compilerVersion: "test"))
        let output = try await writer.write(index)
        #expect(output.text.contains("var computed: Swift.Int"))
    }

    @Test func failedSourcePreservesOnlyPreviouslyCompletedSources() async throws {
        var index = SymbolIndexStore()
        do {
            try await index.ingest(sources: [
                .mangledSymbols(["_$s7Example3FooVMn"], context: Self.context),
                .mangledSymbols(["$s7Example3FooV8computedSivg", "invalid"], context: Self.context),
            ])
            Issue.record("Expected source parsing to fail")
        } catch {
            #expect(index.declarationsByID.values.map(\.name) == ["Foo"])
            #expect(index.exportedSymbols == ["$s7Example3FooVMn"])
        }
    }

    @Test func cancelledSelectionPreservesTheIndex() async throws {
        let task = Task {
            var index = SymbolIndexStore()
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                try await index.ingest(sources: [.mangledSymbols(["_$s7Example3FooVMn"], context: Self.context)])
                Issue.record("Expected cancellation")
            } catch is CancellationError {
                #expect(index.declarationsByID.isEmpty)
            }
        }
        try await task.value
    }
}
