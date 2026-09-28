import SwiftIndexing

/// Preserves a successfully parsed input even when declaration extraction is unsupported.
public struct SymbolRecord: Sendable {
    public typealias Role = ParsedSymbolRecord.Role

    /// The input spelling from extraction, or the normalized spelling in a store.
    public let mangledSymbol: String
    /// All observed spellings, including an optional linker underscore.
    public internal(set) var mangledSymbols: Set<String>
    public let demangledSymbol: DemangledNode
    public let role: Role
    public let declarationIDs: Set<SymbolDeclaration.ID>

    internal init(mangledSymbol: String, demangledSymbol: DemangledNode, role: Role,
                  declarationIDs: Set<SymbolDeclaration.ID>) {
        self.mangledSymbol = mangledSymbol
        self.mangledSymbols = [mangledSymbol]
        self.demangledSymbol = demangledSymbol
        self.role = role
        self.declarationIDs = declarationIDs
    }
}
