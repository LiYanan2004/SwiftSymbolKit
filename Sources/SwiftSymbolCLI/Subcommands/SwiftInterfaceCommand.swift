import ArgumentParser
import Foundation
import OSLog
import SwiftIndexing
import SwiftSymbolIndexStore

struct SwiftInterfaceCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "interface",
        abstract: "Reconstruct a Swift interface from a TBD file.",
        discussion: "Reconstructs declarations recoverable from exported symbols. Validate the output with a Swift compiler before importing it."
    )
    
    @Argument(help: "The local TBD file path.")
    var input: String
    
    @Option(name: .shortAndLong, help: "The output file path. Defaults to standard output.")
    var output: String?
    
    @Flag(
        inversion: .prefixedNo,
        help: "Try to recover opaque type conformances from MachO images."
    )
    var parseOpaqueReturnType = true
    
    @Option(help: "A Mach-O file to parse for opaque recovery. Defaults to the current system dyld shared cache.")
    var imagePath: String?
    
    mutating func run() async throws {
        let inputURL = URL(fileURLWithPath: (input as NSString).expandingTildeInPath)
        let stub = try TextBasedStub(yaml: String(contentsOf: inputURL, encoding: .utf8))
        if imagePath != nil, !parseOpaqueReturnType {
            throw ValidationError("--image-path requires --parse-opaque-return-type.")
        }
        let moduleName = inputURL.deletingPathExtension().lastPathComponent
        let descriptors = stub.swiftSymbolTargets.filter { $0.key.hasSuffix("QOMQ") }
        let opaqueIndexingResult: IndexingResult?
        if parseOpaqueReturnType, !descriptors.isEmpty {
            opaqueIndexingResult = try await LoadedImageSource(
                imagePath: imagePath.map(\.expandingTildeInPath),
                imageInstallName: stub.installName,
                descriptorSymbols: Array(descriptors.keys),
                context: .init(moduleName: moduleName, targets: stub.targets),
                descriptorSymbolTargets: descriptors
            ).read()
        } else { opaqueIndexingResult = nil }
        let selectedTargets = opaqueIndexingResult?.context.targets ?? stub.targets
        let symbolTargets = stub.swiftSymbolTargets.compactMapValues { targets -> Set<IndexingTarget>? in
            let coverage = targets.intersection(selectedTargets)
            return coverage.isEmpty ? nil : coverage
        }
        guard !symbolTargets.isEmpty else {
            throw ValidationError("The TBD file contains no exported Swift symbols.")
        }
        
        let context = IndexingContext(
            moduleName: moduleName,
            targets: selectedTargets
        )
        var store = SymbolIndexStore()
        try await mergeMangledSymbols(
            symbolTargets,
            context: context,
            location: inputURL.absoluteString,
            into: &store
        )
        if let opaqueIndexingResult {
            try store.merge(opaqueIndexingResult)
        }
        
        let writer = SwiftInterfaceWriter(configuration: .init(moduleName: context.moduleName))
        let interface = try await writer.write(store)
        writeDiagnostics(interface.diagnostics)
        if let output {
            let outputURL = URL(fileURLWithPath: (output as NSString).expandingTildeInPath)
            guard outputURL.standardizedFileURL != inputURL.standardizedFileURL else {
                throw ValidationError("The output file must differ from the input TBD file.")
            }
            try interface.text.write(to: outputURL, atomically: true, encoding: .utf8)
        } else {
            FileHandle.standardOutput.write(Data(interface.text.utf8))
        }
    }
}

fileprivate extension SwiftInterfaceCommand {
    func mergeMangledSymbols(
        _ symbolTargets: [String: Set<IndexingTarget>],
        context: IndexingContext,
        location: String,
        into symbolIndexStore: inout SymbolIndexStore
    ) async throws {
        try Task.checkCancellation()
        let mangledSymbols = symbolTargets.keys.sorted()
        let source = SymbolEvidenceSource(
            kind: .mangledSymbols,
            location: location,
            artifactIdentifier: location,
            lineageIdentifier: location
        )
        let windowSize = 4096
        for start in stride(from: 0, to: mangledSymbols.count, by: windowSize) {
            let inputs = Array(mangledSymbols[start..<min(start + windowSize, mangledSymbols.count)])
            let results = try await ParallelMap.map(inputs) { mangledSymbol in
                Result {
                    try MangledSymbolSource(
                        exportedSymbols: [mangledSymbol],
                        context: context,
                        exportedSymbolTargets: [mangledSymbol: symbolTargets[mangledSymbol]!],
                        source: source
                    ).parse()
                }
            }
            for (mangledSymbol, result) in zip(inputs, results) {
                try Task.checkCancellation()
                switch result {
                    case .success(let indexingResult):
                        _ = try symbolIndexStore.merge(indexingResult)
                    case .failure(let error):
                        Loggers.symbolExtraction.error(
                            "Failed to parse symbol: \(String(describing: error), privacy: .public). Symbol: \(mangledSymbol, privacy: .public)"
                        )
                        throw error
                }
            }
        }
    }
    
    func writeDiagnostics(_ diagnostics: [SymbolDiagnostic]) {
        for diagnostic in diagnostics {
            let logger: Logger
            switch diagnostic.kind {
                case .unsupportedSymbol:
                    logger = Loggers.symbolExtraction
                case .conflictingInformation:
                    logger = Loggers.symbolMerging
                case .incompleteDeclaration:
                    logger = Loggers.interfaceGeneration
            }
            switch diagnostic.severity {
                case .info:
                    logger.info("\(diagnostic.message, privacy: .public)")
                case .warning:
                    logger.warning("\(diagnostic.message, privacy: .public)")
                case .error:
                    logger.error("\(diagnostic.message, privacy: .public)")
            }
        }
    }
}

extension String {
    var expandingTildeInPath: String {
        (self as NSString).expandingTildeInPath
    }
}
