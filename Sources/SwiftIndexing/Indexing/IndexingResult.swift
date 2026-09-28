/// Normalized input shared by all adapters. The store owns identity matching,
/// conflict resolution, new declaration admission and export eligibility.
public struct IndexingResult: Sendable {
    public let source: SymbolEvidenceSource
    public let context: IndexingContext
    public let declarations: [SymbolDeclaration]
    public let symbolRecords: [SymbolRecord]
    public let conformances: [ProtocolConformance]
    public let protocolRequirements: [ProtocolConformanceRequirement]
    public let runtimeSymbols: [RuntimeSymbolRecord]
    public let diagnostics: [SymbolDiagnostic]
    /// Export evidence must come from the selected TBD/linker surface.
    /// Runtime discovery alone must leave this empty.
    public let exportedSymbols: Set<String>
    /// Target coverage for each linker spelling in exportedSymbols.
    public let exportedSymbolTargets: [String: Set<IndexingTarget>]
    /// Includes unresolved source identities and source-only declarations such as aliases.
    public let observations: [SymbolObservation]

    public init(source: SymbolEvidenceSource, context: IndexingContext,
                declarations: [SymbolDeclaration] = [], symbolRecords: [SymbolRecord] = [],
                conformances: [ProtocolConformance] = [],
                protocolRequirements: [ProtocolConformanceRequirement] = [],
                runtimeSymbols: [RuntimeSymbolRecord] = [], diagnostics: [SymbolDiagnostic] = [],
                exportedSymbols: Set<String> = [],
                exportedSymbolTargets: [String: Set<IndexingTarget>]? = nil, observations: [SymbolObservation] = []) {
        self.source = source
        self.context = context
        self.declarations = declarations
        self.symbolRecords = symbolRecords
        self.conformances = conformances
        self.protocolRequirements = protocolRequirements
        self.runtimeSymbols = runtimeSymbols
        self.diagnostics = diagnostics
        self.exportedSymbols = exportedSymbols
        self.exportedSymbolTargets = exportedSymbolTargets
            ?? Dictionary(uniqueKeysWithValues: exportedSymbols.map { ($0, context.targets) })
        self.observations = observations
    }
}

