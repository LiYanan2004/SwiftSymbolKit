import SwiftDemangle

/// Preserves a successfully parsed input even when declaration extraction is unsupported.
public struct SymbolRecord {
    public enum Role {
        // Declaration-related symbols.
        case declaration
        case metadata
        case descriptor
        case accessor

        // Auxiliary and unclassified symbols.
        case auxiliary
        case unsupported
    }

    public let mangledSymbol: String
    public let demangledSymbol: SwiftSymbol
    public let role: Role
    public let declarationIDs: Set<SymbolDeclaration.ID>
}
