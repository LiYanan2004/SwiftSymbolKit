public struct SymbolEvidence: Sendable {
    public let source: SymbolEvidenceSource
    public let observation: SymbolObservation

    public init(source: SymbolEvidenceSource, observation: SymbolObservation) {
        self.source = source
        self.observation = observation
    }
}
