import SwiftIndexing
/// Stored in the index independently of source visibility and fact confidence.
/// These assessments must account for accessor roles and referenced dependencies.
public enum SymbolExportAssessment: Sendable {
    case unresolved
    case supportedByExports(Set<String>)
    case sourceOnly(dependencies: Set<SymbolDeclaration.ID>)
    case unavailable(reason: String)
}
