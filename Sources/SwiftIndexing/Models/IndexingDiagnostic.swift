/// An extraction, merge or interface-generation issue with traceable input symbols.
public struct IndexingDiagnostic: Sendable {
    public enum Kind: Hashable, Sendable {
        case unsupportedSymbol
        case conflictingInformation
        case incompleteDeclaration
    }

    public enum Severity: Sendable {
        case info
        case warning
        case error
    }

    public let severity: Severity
    public let kind: Kind
    public let message: String
    public let mangledSymbols: Set<String>
    public let declarationID: ParsedDeclaration.ID?

    internal init(kind: Kind, message: String, mangledSymbols: Set<String>,
         declarationID: ParsedDeclaration.ID?, severity: Severity? = nil) {
        self.kind = kind
        self.message = message
        self.mangledSymbols = mangledSymbols
        self.declarationID = declarationID
        self.severity = severity ?? (kind == .conflictingInformation ? .warning : .error)
    }
}
