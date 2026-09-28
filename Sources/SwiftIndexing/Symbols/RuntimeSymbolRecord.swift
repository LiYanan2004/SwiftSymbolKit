/// A runtime support symbol associated with a class declaration.
/// These records describe exported runtime entry points or data, not source members.
public struct RuntimeSymbolRecord: Sendable {
    public enum Kind: Sendable {
        case classMetadataBaseOffset
        case methodLookupFunction
    }

    public let kind: Kind
    public let declarationID: SymbolDeclaration.ID
    /// Original spellings; full demangle trees are retained in the parsed symbol records.
    public package(set) var mangledSymbols: Set<String>


    package init(kind: Kind, declarationID: SymbolDeclaration.ID, mangledSymbols: Set<String>) {
        self.kind = kind
        self.declarationID = declarationID
        self.mangledSymbols = mangledSymbols
    }
}
