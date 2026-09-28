/// A runtime support symbol associated with a class declaration.
/// These records describe exported runtime entry points or data, not source members.
public struct ParsedRuntimeSymbol: Sendable {
    public enum Kind: Sendable {
        case classMetadataBaseOffset
        case methodLookupFunction
    }

    public let kind: Kind
    public let declarationID: ParsedDeclaration.ID
    /// Original spellings; full demangle trees are retained in the parsed symbol records.
    public let mangledSymbols: Set<String>


    internal init(kind: Kind, declarationID: ParsedDeclaration.ID, mangledSymbols: Set<String>) {
        self.kind = kind
        self.declarationID = declarationID
        self.mangledSymbols = mangledSymbols
    }
}
