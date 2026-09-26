import SwiftDemangle

/// Incrementally assembles a declaration index from mangled Swift symbols.
/// The caller owns synchronization when sharing a store across concurrent work.
public struct SymbolStore {
    public private(set) var index: SymbolIndex

    public init() {
        index = SymbolIndex()
    }

    public struct MergeResult {
        public let affectedDeclarationIDs: Set<SymbolDeclaration.ID>
        public let diagnostics: [SymbolDiagnostic]
    }

    /// Merges one symbol. Algorithm implementation is intentionally pending.
    @discardableResult
    public mutating func merge(_ mangledSymbol: String) throws -> MergeResult {
        // TODO: Parse through parseMangledSwiftSymbol, then use SymbolExtractor.
        // Normalize supported linker prefixes for deduplication while retaining input spelling.
        // Parse/extract before mutation so thrown errors leave the index unchanged.
        // Upsert ancestors and declarations by structural identity; promote context-only
        // evidence when direct symbols arrive. Union accessors and symbol provenance.
        // Merge conformances separately and update parent-to-members lookup tables.
        // Preserve conflicting facts with diagnostics instead of selecting the latest input.
        // Ensure duplicate merges are idempotent and final output is order-independent.
        fatalError("Incremental symbol merging is not implemented")
    }
}
