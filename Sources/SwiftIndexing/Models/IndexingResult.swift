/// Normalized input shared by all adapters. The store owns identity matching,
/// conflict resolution, new declaration admission and export eligibility.
public struct IndexingResult: Sendable {
    public let source: SymbolEvidenceSource
    public let context: IndexingContext?
    public let declarations: [ParsedDeclaration]
    public let symbolRecords: [ParsedSymbolRecord]
    public let conformances: [ParsedConformance]
    public let protocolRequirements: [ParsedProtocolRequirement]
    public let runtimeSymbols: [ParsedRuntimeSymbol]
    public let diagnostics: [IndexingDiagnostic]
    /// Export evidence must come from the selected TBD/linker surface.
    /// Runtime discovery alone must leave this empty.
    public let exportedSymbols: Set<String>
    /// Includes unresolved source identities and source-only declarations such as aliases.
    public let observations: [SymbolObservation]

    public init(source: SymbolEvidenceSource, context: IndexingContext?,
                declarations: [ParsedDeclaration] = [], symbolRecords: [ParsedSymbolRecord] = [],
                conformances: [ParsedConformance] = [],
                protocolRequirements: [ParsedProtocolRequirement] = [],
                runtimeSymbols: [ParsedRuntimeSymbol] = [], diagnostics: [IndexingDiagnostic] = [],
                exportedSymbols: Set<String> = [], observations: [SymbolObservation] = []) {
        self.source = source
        self.context = context
        self.declarations = declarations
        self.symbolRecords = symbolRecords
        self.conformances = conformances
        self.protocolRequirements = protocolRequirements
        self.runtimeSymbols = runtimeSymbols
        self.diagnostics = diagnostics
        self.exportedSymbols = exportedSymbols
        self.observations = observations
    }
}
