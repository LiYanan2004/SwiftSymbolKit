import SwiftDemangle

/// Incrementally indexes declarations and relationships from mangled Swift symbols.
/// The caller owns synchronization when sharing a store across concurrent work.
public struct SymbolIndexStore {
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
        runtimeSymbolsByIdentity.keys.sorted { $0.lexicographicallyPrecedes($1) }.map { runtimeSymbolsByIdentity[$0]! }
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

    private struct DiagnosticIdentity: Hashable {
        let kind: SymbolDiagnostic.Kind
        let message: String
        let declarationID: SymbolDeclaration.ID?
        let mangledSymbol: String?
    }
    private var membersByID: [SymbolDeclaration.ID: Set<SymbolDeclaration.ID>] = [:]

    public init() {}

    public func declarations(inModule moduleName: String) -> [SymbolDeclaration] {
        declarationsByID.values.filter {
            guard case .module(let owner) = $0.context else { return false }
            return owner == moduleName
        }.sorted { $0.id.structuralKey < $1.id.structuralKey }
    }

    public func members(of declarationID: SymbolDeclaration.ID) -> [SymbolDeclaration] {
        (membersByID[declarationID] ?? []).compactMap { declarationsByID[$0] }
            .sorted { $0.id.structuralKey < $1.id.structuralKey }
    }

    public struct MergeResult {
        /// Declarations whose facts or source spellings changed, including ancestors.
        public let affectedDeclarationIDs: Set<SymbolDeclaration.ID>
        /// Diagnostics introduced or updated by this merge.
        public let diagnostics: [SymbolDiagnostic]
    }

    /// Merges one symbol, preserving its original spelling and all observed facts.
    /// Repeating an input has no effect. Parsing and extraction finish before mutation.
    @discardableResult
    public mutating func merge(_ mangledSymbol: String) throws -> MergeResult {
        let normalizedSymbol = Self.normalizedSymbol(mangledSymbol)
        if symbolRecordsByMangledName[normalizedSymbol]?.mangledSymbols.contains(mangledSymbol) == true {
            return MergeResult(affectedDeclarationIDs: [], diagnostics: [])
        }
        return merge(try Self.extract(mangledSymbol))
    }

    /// An invalid symbol encountered by a bulk merge. Earlier inputs remain indexed.
    public struct MergeError: Error {
        public let mangledSymbol: String
        public let underlyingError: any Error
    }

    /// Extracts bounded batches and merges in input order.
    /// Reports the first invalid input, preserving the same prefix as individual merges.
    public mutating func merge(contentsOf mangledSymbols: [String]) throws {
        try Task.checkCancellation()
        // Bound temporary demangle trees independently of the total input size.
        let windowSize = 4096
        for start in stride(from: 0, to: mangledSymbols.count, by: windowSize) {
            var seenSymbols: Set<String> = []
            let inputs = mangledSymbols[start..<min(start + windowSize, mangledSymbols.count)].filter {
                seenSymbols.insert($0).inserted
                    && symbolRecordsByMangledName[Self.normalizedSymbol($0)]?.mangledSymbols.contains($0) != true
            }
            let results = inputs.map { symbol in
                Result { try Self.extract(symbol) }
            }
            for (symbol, result) in zip(inputs, results) {
                try Task.checkCancellation()
                switch result {
                case .success(let extraction): _ = merge(extraction)
                case .failure(let error): throw MergeError(mangledSymbol: symbol, underlyingError: error)
                }
            }
        }
    }
}

fileprivate extension SymbolIndexStore {
    static func normalizedSymbol(_ mangledSymbol: String) -> String {
        if ["_$s", "_$S", "_$e", "__T", "_async_Main"].contains(where: mangledSymbol.hasPrefix) {
            return String(mangledSymbol.dropFirst())
        }
        return mangledSymbol
    }

    static func extract(_ mangledSymbol: String) throws -> SymbolExtractor.ExtractionResult {
        let symbol = try SwiftSymbol(normalizedSymbol(mangledSymbol))
        return try SymbolExtractor().extract(symbol, mangledSymbol: mangledSymbol)
    }

    mutating func merge(_ extraction: SymbolExtractor.ExtractionResult) -> MergeResult {
        let mangledSymbol = extraction.record.mangledSymbol
        let normalizedSymbol = Self.normalizedSymbol(mangledSymbol)
        var affectedDeclarationIDs: Set<SymbolDeclaration.ID> = []
        var incomingDiagnostics = extraction.diagnostics

        for declaration in extraction.declarations {
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

        for conformance in extraction.conformances {
            let identity = conformance.mergeIdentity
            if conformancesByIdentity[identity] != nil {
                conformancesByIdentity[identity]?.mangledSymbols.formUnion(conformance.mangledSymbols)
            } else {
                conformancesByIdentity[identity] = conformance
            }
        }
        for requirement in extraction.protocolRequirements {
            let identity = requirement.structuralIdentity
            if requirementsByIdentity[identity] != nil {
                requirementsByIdentity[identity]?.mangledSymbols.formUnion(requirement.mangledSymbols)
            } else {
                requirementsByIdentity[identity] = requirement
            }
            affectedDeclarationIDs.insert(requirement.protocolID)
        }
        for runtimeSymbol in extraction.runtimeSymbols {
            let identity = runtimeSymbol.structuralIdentity
            if runtimeSymbolsByIdentity[identity] != nil {
                runtimeSymbolsByIdentity[identity]?.mangledSymbols.formUnion(runtimeSymbol.mangledSymbols)
            } else {
                runtimeSymbolsByIdentity[identity] = runtimeSymbol
            }
            affectedDeclarationIDs.insert(runtimeSymbol.declarationID)
        }

        var record = SymbolRecord(mangledSymbol: normalizedSymbol, demangledSymbol: extraction.record.demangledSymbol,
                                  role: extraction.record.role, declarationIDs: extraction.record.declarationIDs)
        record.mangledSymbols = (symbolRecordsByMangledName[normalizedSymbol]?.mangledSymbols ?? []).union([mangledSymbol])
        symbolRecordsByMangledName[normalizedSymbol] = record

        var updatedDiagnostics: [SymbolDiagnostic] = []
        for diagnostic in incomingDiagnostics {
            let identity = DiagnosticIdentity(kind: diagnostic.kind, message: diagnostic.message,
                declarationID: diagnostic.declarationID,
                mangledSymbol: diagnostic.declarationID == nil ? normalizedSymbol : nil)
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
