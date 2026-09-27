/// A runtime support symbol associated with a class declaration.
/// These records describe exported runtime entry points or data, not source members.
public struct RuntimeSymbolRecord {
    public enum Kind {
        case classMetadataBaseOffset
        case methodLookupFunction
    }

    public let kind: Kind
    public let declarationID: SymbolDeclaration.ID
    /// Original spellings; full demangle trees remain available in SymbolIndexStore.symbolRecordsByMangledName.
    public internal(set) var mangledSymbols: Set<String>

    internal var structuralIdentity: [String] {
        [declarationID.structuralKey, String(describing: kind)]
    }
}
