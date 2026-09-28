import SwiftIndexing

/// Indexes declarations, relationships and evidence contributed by multiple sources.
///
/// The caller owns synchronization when sharing a store across concurrent work.
public struct SymbolIndexStore: Sendable {
    public private(set) var declarationsByID: [SymbolDeclaration.ID: SymbolDeclaration] = [:]
    /// Keyed by mangling with the optional linker underscore removed.
    public private(set) var symbolRecordsByMangledName: [String: SymbolRecord] = [:]
    public var conformances: [ProtocolConformance] {
        conformancesByIdentity.keys
            .sorted { $0.lexicographicallyPrecedes($1) }
            .map { conformancesByIdentity[$0]! }
    }
    /// Observed protocol requirements; exported symbols may omit other constraints.
    public var protocolRequirements: [ProtocolConformanceRequirement] {
        requirementsByIdentity.keys
            .sorted { $0.lexicographicallyPrecedes($1) }
            .map { requirementsByIdentity[$0]! }
    }
    /// Class runtime support symbols, kept separately from source declarations.
    public var runtimeSymbols: [RuntimeSymbolRecord] {
        runtimeSymbolsByIdentity.keys
            .sorted { $0.lexicographicallyPrecedes($1) }
            .map { runtimeSymbolsByIdentity[$0]! }
    }
    public var diagnostics: [SymbolDiagnostic] {
        diagnosticsByIdentity.values.sorted {
            [$0.declarationID?.structuralKey ?? "", $0.message, $0.mangledSymbols.min() ?? ""]
                .lexicographicallyPrecedes([$1.declarationID?.structuralKey ?? "", $1.message, $1.mangledSymbols.min() ?? ""])
        }
    }
    private var conformancesByIdentity: [[String]: ProtocolConformance] = [:]
    private var requirementsByIdentity: [[String]: ProtocolConformanceRequirement] = [:]
    private var runtimeSymbolsByIdentity: [[String]: RuntimeSymbolRecord] = [:]
    private var diagnosticsByIdentity: [DiagnosticIdentity: SymbolDiagnostic] = [:]
    private var conflictingDeclarationIDs: Set<SymbolDeclaration.ID> = []

    private struct DiagnosticIdentity: Hashable, Sendable {
        let kind: SymbolDiagnostic.Kind
        let message: String
        let declarationID: SymbolDeclaration.ID?
        let mangledSymbol: String?
    }
    private var membersByID: [SymbolDeclaration.ID: Set<SymbolDeclaration.ID>] = [:]

    public private(set) var context: IndexingContext?
    public private(set) var primarySource: SymbolEvidenceSource?
    public private(set) var sources: Set<SymbolEvidenceSource> = []
    public private(set) var sourcesByDeclarationID: [SymbolDeclaration.ID: Set<SymbolEvidenceSource>] = [:]
    /// Normalized symbols supported by the selected TBD/export surface.
    public private(set) var exportedSymbols: Set<String> = []
    public private(set) var evidence: [SymbolEvidence] = []
    public private(set) var resolvedFactsBySubject: [SymbolResolvedSubject: [ResolvedSymbolFact]] = [:]
    public private(set) var exportAssessmentsByDeclarationID: [SymbolDeclaration.ID: SymbolExportAssessment] = [:]
    public private(set) var reconciliationIssues: [SymbolIndexIssue] = []

    /// The first primary contribution establishes the context.
    public init() {}

    public enum IngestionError: Error {
        case incompatibleContext
        case primarySourceRequired
        case differentPrimarySource
        case invalidExportEvidence
    }

    /// The single mutation boundary for parsed input. Matching, reconciliation and
    /// export eligibility belong to the index; source adapters only produce facts.
    @discardableResult
    public mutating func merge(_ result: IndexingResult) throws -> MergeResult {
        if let context, let incomingContext = result.context {
            guard incomingContext == context else { throw IngestionError.incompatibleContext }
        }
        if result.source.kind == .mangledSymbols {
            if let primarySource {
                guard primarySource == result.source else { throw IngestionError.differentPrimarySource }
                guard context == result.context else { throw IngestionError.incompatibleContext }
            }
        } else if primarySource == nil {
            throw IngestionError.primarySourceRequired
        }

        guard result.source.kind == .mangledSymbols, result.observations.isEmpty else {
            fatalError("TODO: Match requested supplemental information, validate related observations, and reconcile evidence.")
        }

        let recordSymbols = Set(result.symbolRecords.map { MangledSymbolSource.normalizedSymbol($0.mangledSymbol) })
        let incomingExports = Set(result.exportedSymbols.map(MangledSymbolSource.normalizedSymbol))
        let supportedDeclarationIDs = Set(result.symbolRecords.flatMap(\.declarationIDs))
        guard recordSymbols == incomingExports,
              Set(result.declarations.map(\.id)).isSubset(of: supportedDeclarationIDs) else {
            throw IngestionError.invalidExportEvidence
        }

        let contribution = SymbolIndexContribution(mangledResult: result)
        let mergeResult = mergeDeclarations(contribution)
        context = result.context
        primarySource = result.source
        sources.insert(result.source)
        for declaration in contribution.declarations {
            sourcesByDeclarationID[declaration.id, default: []].insert(result.source)
        }
        exportedSymbols.formUnion(incomingExports)
        return mergeResult
    }

    public func declarations(inModule moduleName: String) -> [SymbolDeclaration] {
        declarationsByID.values
            .filter {
                guard case .module(let owner) = $0.context else { return false }
                return owner == moduleName
            }
            .sorted { $0.id.structuralKey < $1.id.structuralKey }
    }

    public func members(of declarationID: SymbolDeclaration.ID) -> [SymbolDeclaration] {
        (membersByID[declarationID] ?? [])
            .compactMap { declarationsByID[$0] }
            .sorted { $0.id.structuralKey < $1.id.structuralKey }
    }

    public struct MergeResult {
        /// Declarations whose facts or source spellings changed, including ancestors.
        public let affectedDeclarationIDs: Set<SymbolDeclaration.ID>
        /// Diagnostics introduced or updated by this merge.
        public let diagnostics: [SymbolDiagnostic]

        internal init(affectedDeclarationIDs: Set<SymbolDeclaration.ID>, diagnostics: [SymbolDiagnostic]) {
            self.affectedDeclarationIDs = affectedDeclarationIDs
            self.diagnostics = diagnostics
        }
    }
}

fileprivate extension SymbolIndexStore {
    mutating func mergeDeclarations(_ contribution: SymbolIndexContribution) -> MergeResult {
        var affectedDeclarationIDs: Set<SymbolDeclaration.ID> = []
        var incomingDiagnostics = contribution.diagnostics

        for declaration in contribution.declarations {
            var merged = declaration
            if let existing = declarationsByID[declaration.id] {
                // Identity includes the signature, labels and context. Keep unexpected
                // disagreements traceable through the original symbol records.
                let existingFacts = existing.mergeFacts
                let incomingFacts = declaration.mergeFacts
                merged = incomingFacts.lexicographicallyPrecedes(existingFacts) ? declaration : existing
                merged.evidence = existing.evidence == .direct || declaration.evidence == .direct ? .direct : .contextOnly
                merged.accessors.formUnion(existing.accessors)
                merged.accessors.formUnion(declaration.accessors)
                merged.mangledSymbols.formUnion(existing.mangledSymbols)
                merged.mangledSymbols.formUnion(declaration.mangledSymbols)
                if existingFacts != incomingFacts || conflictingDeclarationIDs.contains(declaration.id) {
                    incomingDiagnostics.append(SymbolDiagnostic(
                        kind: .conflictingInformation,
                        message: "Conflicting declaration facts; original symbols retain all observations.",
                        mangledSymbols: merged.mangledSymbols, declarationID: declaration.id
                    ))
                }
                if existingFacts == merged.mergeFacts && existing.evidence == merged.evidence
                    && existing.accessors == merged.accessors && existing.mangledSymbols == merged.mangledSymbols {
                    continue
                }
            }
            declarationsByID[declaration.id] = merged
            affectedDeclarationIDs.insert(declaration.id)
            switch declaration.context {
            case .module: break
            case .declaration(let parentID):
                membersByID[parentID, default: []].insert(declaration.id)
            case .typeExtension(let context):
                membersByID[context.extendedType, default: []].insert(declaration.id)
            }
        }

        for conformance in contribution.conformances {
            let identity = conformance.mergeIdentity
            if conformancesByIdentity[identity] != nil {
                conformancesByIdentity[identity]?.mangledSymbols.formUnion(conformance.mangledSymbols)
            } else {
                conformancesByIdentity[identity] = conformance
            }
        }
        for requirement in contribution.protocolRequirements {
            let identity = requirement.structuralIdentity
            if requirementsByIdentity[identity] != nil {
                requirementsByIdentity[identity]?.mangledSymbols.formUnion(requirement.mangledSymbols)
            } else {
                requirementsByIdentity[identity] = requirement
            }
            affectedDeclarationIDs.insert(requirement.protocolID)
        }
        for runtimeSymbol in contribution.runtimeSymbols {
            let identity = runtimeSymbol.structuralIdentity
            if runtimeSymbolsByIdentity[identity] != nil {
                runtimeSymbolsByIdentity[identity]?.mangledSymbols.formUnion(runtimeSymbol.mangledSymbols)
            } else {
                runtimeSymbolsByIdentity[identity] = runtimeSymbol
            }
            affectedDeclarationIDs.insert(runtimeSymbol.declarationID)
        }

        for incomingRecord in contribution.symbolRecords {
            let normalizedSymbol = MangledSymbolSource.normalizedSymbol(incomingRecord.mangledSymbol)
            var record = SymbolRecord(mangledSymbol: normalizedSymbol, demangledSymbol: incomingRecord.demangledSymbol,
                                      role: incomingRecord.role, declarationIDs: incomingRecord.declarationIDs)
            record.mangledSymbols = (symbolRecordsByMangledName[normalizedSymbol]?.mangledSymbols ?? [])
                .union(incomingRecord.mangledSymbols)
            symbolRecordsByMangledName[normalizedSymbol] = record
        }

        var updatedDiagnostics: [SymbolDiagnostic] = []
        for diagnostic in incomingDiagnostics {
            let identity = DiagnosticIdentity(kind: diagnostic.kind, message: diagnostic.message,
                declarationID: diagnostic.declarationID,
                mangledSymbol: diagnostic.declarationID == nil ? diagnostic.mangledSymbols.sorted().first.map(MangledSymbolSource.normalizedSymbol) : nil)
            let merged = SymbolDiagnostic(
                kind: diagnostic.kind, message: diagnostic.message,
                mangledSymbols: diagnostic.mangledSymbols.union(diagnosticsByIdentity[identity]?.mangledSymbols ?? []),
                declarationID: diagnostic.declarationID, severity: diagnostic.severity
            )
            diagnosticsByIdentity[identity] = merged
            if diagnostic.kind == .conflictingInformation, let identifier = diagnostic.declarationID {
                conflictingDeclarationIDs.insert(identifier)
            }
            updatedDiagnostics.append(merged)
        }
        return MergeResult(affectedDeclarationIDs: affectedDeclarationIDs, diagnostics: updatedDiagnostics)
    }
}

fileprivate extension SymbolDeclaration {
    /// Evidence, accessors and provenance accumulate independently of declaration facts.
    var mergeFacts: [String] {
        let contextFields: [String]
        switch context {
        case .module(let name): contextFields = ["module", name]
        case .declaration(let identifier): contextFields = ["declaration", identifier.structuralKey]
        case .typeExtension(let context):
            contextFields = ["extension", context.moduleName, context.extendedType.structuralKey,
                             context.genericSignature?.declarationKey ?? ""]
        }
        return [String(describing: kind), name, nameNode?.declarationKey ?? "", String(isStatic),
                signature?.declarationKey ?? "", genericSignature?.declarationKey ?? "",
                parameterLabels == nil ? "unknown labels" : "labels"]
            + (parameterLabels ?? []) + contextFields
    }
}

fileprivate extension ProtocolConformance {
    var mergeIdentity: [String] {
        [moduleName, conformingType.declarationKey, protocolType.declarationKey, genericSignature?.declarationKey ?? ""]
    }
}
