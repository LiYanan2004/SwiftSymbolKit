import SwiftIndexing

/// A canonical subject in the unified index, including admitted source-only declarations.
public enum SymbolResolvedSubject: Hashable, Sendable {
    case declaration(SymbolDeclaration.ID)
    case module(String)
}

public enum SymbolDeclarationMatch: Sendable {
    case matched(SymbolResolvedSubject)
    case unmatched
    /// The policy must retain ambiguity instead of choosing the first overload.
    case ambiguous([SymbolResolvedSubject])
}

public struct ResolvedSymbolFact: Sendable {
    public enum Confidence: Sendable {
        case singleSource
        /// Agreement across independent lineages, after matching and ABI validation.
        case corroborated
    }

    public let subject: SymbolResolvedSubject
    public let fact: SymbolSupplementalFact
    public let confidence: Confidence
    public let evidence: [SymbolEvidence]

    public init(
        subject: SymbolResolvedSubject,
        fact: SymbolSupplementalFact,
        confidence: Confidence,
        evidence: [SymbolEvidence]
    ) {
        self.subject = subject
        self.fact = fact
        self.confidence = confidence
        self.evidence = evidence
    }
}

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
