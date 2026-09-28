import SwiftDemangle

/// Preserves a successfully parsed input even when declaration extraction is unsupported.
public struct ParsedSymbolRecord: Sendable {
    public enum Role: Equatable, Sendable {
        // Declaration-related symbols.
        case declaration
        case metadata
        case descriptor
        case accessor

        // Auxiliary and unclassified symbols.
        /// Identifies the auxiliary node; the full tree retains any additional attributes.
        case auxiliary(SwiftSymbol.Kind)
        case unsupported
    }

    /// The input spelling from extraction, or the normalized spelling in a store.
    public let mangledSymbol: String
    /// All observed spellings, including an optional linker underscore.
    public let mangledSymbols: Set<String>
    public let demangledSymbol: SwiftSymbol
    public let role: Role
    public let declarationIDs: Set<ParsedDeclaration.ID>

    internal init(mangledSymbol: String, demangledSymbol: SwiftSymbol, role: Role,
                  declarationIDs: Set<ParsedDeclaration.ID>) {
        self.mangledSymbol = mangledSymbol
        self.mangledSymbols = [mangledSymbol]
        self.demangledSymbol = demangledSymbol
        self.role = role
        self.declarationIDs = declarationIDs
    }
}
