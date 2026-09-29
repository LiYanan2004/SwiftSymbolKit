/// A supplemental fact together with its subject and provenance.
public struct SymbolEvidence: Sendable {
    public let source: SymbolEvidenceSource
    public let subject: SymbolEvidenceSubject
    public let fact: SymbolSupplementalFact
    /// Source line, JSON pointer, or image/section offset within the artifact.
    public let location: String

    public init(source: SymbolEvidenceSource, subject: SymbolEvidenceSubject,
                fact: SymbolSupplementalFact, location: String) {
        self.source = source
        self.subject = subject
        self.fact = fact
        self.location = location
    }
}
