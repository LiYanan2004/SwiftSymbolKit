import SwiftIndexing

extension SymbolIndexStore {
    /// Reads a source, then merges its normalized indexing result into the store.
    @discardableResult
    public mutating func ingest(_ source: any IndexingSource) async throws -> MergeResult {
        try Task.checkCancellation()
        let indexingResult = try await source.read()
        try Task.checkCancellation()
        return try merge(indexingResult)
    }
}
