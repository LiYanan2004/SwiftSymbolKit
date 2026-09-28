import SwiftDemangle

/// Parses the target-filtered symbols supplied by the authoritative export surface.
public struct MangledSymbolSource: IndexingSource {
    public let context: IndexingContext
    public let source: SymbolEvidenceSource
    public let exportedSymbols: [String]
    public let exportedSymbolTargets: [String: Set<IndexingTarget>]

    public init(exportedSymbols: [String], context: IndexingContext,
                exportedSymbolTargets: [String: Set<IndexingTarget>]? = nil,
                source: SymbolEvidenceSource = .init(kind: .mangledSymbols, location: "caller",
                    artifactIdentifier: "caller-supplied-exports", lineageIdentifier: "caller-supplied-exports")) {
        self.exportedSymbols = exportedSymbols
        self.context = context
        self.exportedSymbolTargets = exportedSymbolTargets
            ?? Dictionary(uniqueKeysWithValues: Set(exportedSymbols).map { ($0, context.targets) })
        self.source = source
    }

    public func read() async throws -> IndexingResult {
        try parse()
    }

    /// Shared by synchronous and asynchronous indexing entry points within this target.
    package func parse() throws -> IndexingResult {
        guard context.isValid else { throw IndexingSourceError.invalidContext }
        guard Set(exportedSymbolTargets.keys) == Set(exportedSymbols),
              exportedSymbolTargets.values.allSatisfy({ !$0.isEmpty && $0.isSubset(of: context.targets) }) else {
            throw IndexingSourceError.invalidSymbolTargets
        }
        var extractions: [SymbolExtractor.ExtractionResult] = []
        for mangledSymbol in exportedSymbols {
            try Task.checkCancellation()
            let symbol = try SwiftSymbol(MangledSymbolSource.normalizedSymbol(mangledSymbol))
            extractions.append(try SymbolExtractor().extract(symbol, mangledSymbol: mangledSymbol))
        }
        return IndexingResult(
            source: source,
            context: context,
            declarations: extractions.flatMap(\.declarations),
            symbolRecords: extractions.map(\.record),
            conformances: extractions.flatMap(\.conformances),
            protocolRequirements: extractions.flatMap(\.protocolRequirements),
            runtimeSymbols: extractions.flatMap(\.runtimeSymbols),
            diagnostics: extractions.flatMap(\.diagnostics),
            exportedSymbols: Set(exportedSymbols),
            exportedSymbolTargets: exportedSymbolTargets
        )
    }
}

extension MangledSymbolSource {
    package static func normalizedSymbol(_ mangledSymbol: String) -> String {
        if ["_$s", "_$S", "_$e", "__T", "_async_Main"].contains(where: mangledSymbol.hasPrefix) {
            return String(mangledSymbol.dropFirst())
        }
        return mangledSymbol
    }
}
