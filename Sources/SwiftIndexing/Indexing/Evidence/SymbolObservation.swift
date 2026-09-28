public struct SymbolObservation: Sendable {
    public let subject: SymbolEvidenceSubject
    public let fact: SymbolSupplementalFact
    /// Source line, JSON pointer, or image/section offset within the artifact.
    public let location: String

    public init(subject: SymbolEvidenceSubject, fact: SymbolSupplementalFact, location: String) {
        self.subject = subject
        self.fact = fact
        self.location = location
    }
}

