import SwiftIndexing

extension SymbolIndexStore {
    /// Reads a source outside the store, then submits its normalized contribution.
    @discardableResult
    public mutating func ingest(_ source: any IndexingSource) async throws -> MergeResult {
        try Task.checkCancellation()
        let contribution = try await source.read()
        try Task.checkCancellation()
        return try merge(contribution)
    }
}
