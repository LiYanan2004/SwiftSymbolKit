import SwiftIndexing

extension SymbolSupplementalFact {
    /// A fact resolved against the index, with its canonical subject and supporting evidence.
    public struct Resolved: Sendable {
        public let subject: SymbolResolvedSubject
        public let fact: SymbolSupplementalFact
        public let confidence: SymbolSupplementalFactConfidence
        public let evidence: [SymbolEvidence]

        public init(
            subject: SymbolResolvedSubject,
            fact: SymbolSupplementalFact,
            confidence: SymbolSupplementalFactConfidence,
            evidence: [SymbolEvidence]
        ) {
            self.subject = subject
            self.fact = fact
            self.confidence = confidence
            self.evidence = evidence
        }
    }
}
