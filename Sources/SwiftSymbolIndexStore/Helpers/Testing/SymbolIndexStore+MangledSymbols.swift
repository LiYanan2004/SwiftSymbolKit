import SwiftIndexing

@_spi(Testing)
extension SymbolIndexStore {
    /// Synthetic metadata is confined to the symbol-extraction test API.
    private var testingContext: IndexingContext {
        context ?? IndexingContext(moduleName: "Testing", targets: [.init(architecture: .arm64, platform: .macOS)])
    }

    /// Merges one symbol, preserving its original spelling and all observed facts.
    /// Repeating an input has no effect. Parsing and extraction finish before mutation.
    @discardableResult
    public mutating func merge(_ mangledSymbol: String) throws -> MergeResult {
        let normalizedSymbol = MangledSymbolSource.normalizedSymbol(mangledSymbol)
        if symbolRecordsByMangledName[normalizedSymbol]?.mangledSymbols.contains(mangledSymbol) == true {
            return MergeResult(affectedDeclarationIDs: [], diagnostics: [])
        }
        return try merge(try MangledSymbolSource(exportedSymbols: [mangledSymbol], context: testingContext).parse())
    }

    /// An invalid symbol encountered by a bulk merge. Earlier inputs remain indexed.
    public struct MergeError: Error {
        public let mangledSymbol: String
        public let underlyingError: any Error
    }

    /// Extracts bounded batches in parallel and merges in input order.
    /// Reports the first invalid input, preserving the same prefix as individual merges.
    public mutating func merge(contentsOf mangledSymbols: [String]) async throws {
        try Task.checkCancellation()
        // Bound temporary demangle trees independently of the total input size.
        let windowSize = 4096
        for start in stride(from: 0, to: mangledSymbols.count, by: windowSize) {
            var seenSymbols: Set<String> = []
            let inputs = mangledSymbols[start..<min(start + windowSize, mangledSymbols.count)].filter {
                seenSymbols.insert($0).inserted
                    && symbolRecordsByMangledName[MangledSymbolSource.normalizedSymbol($0)]?.mangledSymbols.contains($0) != true
            }
            let context = testingContext
            let results = try await ParallelMap.map(inputs) { symbol in
                Result {
                    try MangledSymbolSource(exportedSymbols: [symbol], context: context).parse()
                }
            }
            for (symbol, result) in zip(inputs, results) {
                try Task.checkCancellation()
                switch result {
                case .success(let indexingResult): _ = try merge(indexingResult)
                case .failure(let error): throw MergeError(mangledSymbol: symbol, underlyingError: error)
                }
            }
        }
    }
}
