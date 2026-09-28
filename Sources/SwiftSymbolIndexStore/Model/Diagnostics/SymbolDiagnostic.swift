import SwiftIndexing
/// An extraction, merge or interface-generation issue with traceable input symbols.
public struct SymbolDiagnostic: Sendable {
    public typealias Kind = IndexingDiagnostic.Kind

    public typealias Severity = IndexingDiagnostic.Severity

    public let severity: Severity
    public let kind: Kind
    public let message: String
    public let mangledSymbols: Set<String>
    public let declarationID: SymbolDeclaration.ID?

    internal init(kind: Kind, message: String, mangledSymbols: Set<String>,
         declarationID: SymbolDeclaration.ID?, severity: Severity? = nil) {
        self.kind = kind
        self.message = message
        self.mangledSymbols = mangledSymbols
        self.declarationID = declarationID
        self.severity = severity ?? (kind == .conflictingInformation ? .warning : .error)
    }
}
