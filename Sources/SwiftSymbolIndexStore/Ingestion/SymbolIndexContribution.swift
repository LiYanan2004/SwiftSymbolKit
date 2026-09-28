import SwiftIndexing

/// Store-owned, canonical input. Source-local references are resolved before merging.
struct SymbolIndexContribution {
    let source: SymbolEvidenceSource
    let declarations: [SymbolDeclaration]
    let symbolRecords: [SymbolRecord]
    let conformances: [ProtocolConformance]
    let protocolRequirements: [ProtocolConformanceRequirement]
    let runtimeSymbols: [RuntimeSymbolRecord]
    let diagnostics: [SymbolDiagnostic]

    /// Mangled declarations have structural identities. Source-signature matching is
    /// handled separately before this conversion can be used for other input formats.
    init(mangledResult result: IndexingResult) {
        source = result.source
        declarations = result.declarations.map(SymbolDeclaration.init(parsed:))
        symbolRecords = result.symbolRecords.map { record in
            var converted = SymbolRecord(mangledSymbol: record.mangledSymbol,
                demangledSymbol: record.demangledSymbol, role: record.role,
                declarationIDs: Set(record.declarationIDs.map(SymbolDeclaration.ID.init(parsed:))))
            converted.mangledSymbols = record.mangledSymbols
            return converted
        }
        conformances = result.conformances.map {
            ProtocolConformance(conformingType: $0.conformingType, protocolType: $0.protocolType,
                moduleName: $0.moduleName, genericSignature: $0.genericSignature, mangledSymbols: $0.mangledSymbols)
        }
        protocolRequirements = result.protocolRequirements.map {
            ProtocolConformanceRequirement(protocolID: .init(parsed: $0.protocolID),
                associatedTypePath: $0.associatedTypePath, requiredProtocol: $0.requiredProtocol,
                mangledSymbols: $0.mangledSymbols)
        }
        runtimeSymbols = result.runtimeSymbols.map {
            RuntimeSymbolRecord(kind: $0.kind, declarationID: .init(parsed: $0.declarationID),
                                mangledSymbols: $0.mangledSymbols)
        }
        diagnostics = result.diagnostics.map {
            SymbolDiagnostic(kind: $0.kind, message: $0.message, mangledSymbols: $0.mangledSymbols,
                declarationID: $0.declarationID.map(SymbolDeclaration.ID.init(parsed:)), severity: $0.severity)
        }
    }
}

extension SymbolDeclaration.ID {
    init(parsed: ParsedDeclaration.ID) {
        self.init(structuralKey: parsed.structuralKey)
    }
}

extension SymbolDeclaration {
    init(parsed: ParsedDeclaration) {
        self.init(id: .init(parsed: parsed.id), kind: parsed.kind, name: parsed.name, nameNode: parsed.nameNode,
            context: .init(parsed: parsed.context), evidence: parsed.evidence, isStatic: parsed.isStatic,
            signature: parsed.signature, parameterLabels: parsed.parameterLabels,
            genericSignature: parsed.genericSignature, accessors: parsed.accessors, mangledSymbols: parsed.mangledSymbols)
    }
}

fileprivate extension DeclarationContext {
    init(parsed: ParsedDeclarationContext) {
        switch parsed {
        case .module(let name): self = .module(name)
        case .declaration(let reference): self = .declaration(.init(parsed: reference))
        case .typeExtension(let context):
            self = .typeExtension(.init(moduleName: context.moduleName,
                extendedType: .init(parsed: context.extendedType), genericSignature: context.genericSignature))
        }
    }
}
