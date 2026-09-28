import SwiftIndexing

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
