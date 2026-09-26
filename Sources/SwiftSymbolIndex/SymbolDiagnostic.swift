/// An extraction, merge or interface-generation issue with traceable input symbols.
public struct SymbolDiagnostic {
    public enum Kind {
        case unsupportedSymbol
        case conflictingInformation
        case incompleteDeclaration
    }

    public let kind: Kind
    public let message: String
    public let mangledSymbols: Set<String>
    public let declarationID: SymbolDeclaration.ID?
}
