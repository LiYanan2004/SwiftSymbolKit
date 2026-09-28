import SwiftIndexing

public struct SymbolIndexIssue: Sendable {
    public enum Reason: Sendable {
        case unmatchedDeclaration
        case ambiguousDeclaration
        case conflictingEvidence
        case incompatibleABI
        case insufficientExportEvidence
        case unsupportedFact
    }

    public let reason: Reason
    public let message: String
    public let evidence: [SymbolEvidence]

    public init(reason: Reason, message: String, evidence: [SymbolEvidence]) {
        self.reason = reason
        self.message = message
        self.evidence = evidence
    }
}
