import SwiftIndexing

/// A canonical subject in the unified index, including admitted source-only declarations.
public enum SymbolResolvedSubject: Hashable, Sendable {
    case declaration(SymbolDeclaration.ID)
    case module(String)
}
