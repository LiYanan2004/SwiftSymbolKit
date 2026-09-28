import SwiftIndexing

/// A runtime support symbol associated with a class declaration.
/// These records describe exported runtime entry points or data, not source members.
public struct RuntimeSymbolRecord: Sendable {
    public typealias Kind = ParsedRuntimeSymbol.Kind

    public let kind: Kind
    public let declarationID: SymbolDeclaration.ID
    /// Original spellings; full demangle trees remain available in SymbolIndexStore.symbolRecordsByMangledName.
    public internal(set) var mangledSymbols: Set<String>

    internal var structuralIdentity: [String] {
        [declarationID.structuralKey, String(describing: kind)]
    }

    internal init(kind: Kind, declarationID: SymbolDeclaration.ID, mangledSymbols: Set<String>) {
        self.kind = kind
        self.declarationID = declarationID
        self.mangledSymbols = mangledSymbols
    }
}
