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
    
    @OptionGroup(title: "Parsing options")
    var parsingOptions: ParsingOptions

    @OptionGroup(title: "Mach-O input")
    var machOInputOptions: MachOInputOptions

    private var textBasedStub: TextBasedStub!
    
    mutating func validate() throws {
        if machOInputOptions.usesDyldSharedCache, machOInputOptions.imagePath != nil {
            throw ValidationError("--uses-dyld-shared-cache and --image-path are mutually exclusive.")
        }

        if parsingOptions.parseOpaqueReturnType, machOInputOptions.imagePath == nil, !machOInputOptions.usesDyldSharedCache {
            throw ValidationError("--parse-opaque-return-type requires --image-path or --uses-dyld-shared-cache.")
        }
        
        if machOInputOptions.usesDyldSharedCache || machOInputOptions.imagePath != nil,
           !parsingOptions.parseOpaqueReturnType, !parsingOptions.parseContextualKeyword {
            throw ValidationError("Metadata sources require --parse-opaque-return-type or --parse-contextual-keyword.")
        }
        
        let inputURL = URL(fileURLWithPath: input.expandingTildeInPath)
        if let output {
            let outputURL = URL(fileURLWithPath: output.expandingTildeInPath)
            guard outputURL.standardizedFileURL.resolvingSymlinksInPath() != inputURL.standardizedFileURL.resolvingSymlinksInPath() else {
                throw ValidationError("The output file must differ from the input TBD file.")
            }
        }
        
        let stub = try TextBasedStub(yaml: String(contentsOf: inputURL, encoding: .utf8))
        guard !stub.swiftSymbolTargets.isEmpty else {
            throw ValidationError("The TBD file contains no exported Swift symbols.")
        }
        textBasedStub = stub
    }
    
    mutating func run() async throws {
        // Recover image metadata
        let requestedSymbols = textBasedStub.swiftSymbolTargets
        let descriptors = requestedSymbols.filter { parsingOptions.parseOpaqueReturnType && $0.key.hasSuffix("QOMQ") }
        let enumDescriptors = requestedSymbols.filter { parsingOptions.parseContextualKeyword && $0.key.hasSuffix("OMn") }
        let metadataSymbols = descriptors.merging(enumDescriptors) { $0.union($1) }
        let metadataIndexingResult: IndexingResult?
        if machOInputOptions.usesDyldSharedCache || machOInputOptions.imagePath != nil, !metadataSymbols.isEmpty {
            do {
                metadataIndexingResult = try await LoadedImageSource(
                    imagePath: machOInputOptions.imagePath.map(\.expandingTildeInPath),
                    imageInstallName: textBasedStub.installName,
                    descriptorSymbols: Array(descriptors.keys),
                    context: .init(moduleName: textBasedStub.moduleName, targets: textBasedStub.targets),
                    descriptorSymbolTargets: metadataSymbols,
                    enumDescriptorSymbols: Array(enumDescriptors.keys)
                ).read()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if !descriptors.isEmpty { throw error }
                Loggers.interfaceGeneration.warning("Enum case metadata recovery: \(String(describing: error), privacy: .public)")
                metadataIndexingResult = nil
            }
        } else {
            metadataIndexingResult = nil
        }
        
        // Select target coverage
        let orderedTargets = Set(requestedSymbols.values.flatMap { $0 }).sorted { compilerTriple($0) < compilerTriple($1) }
        let selectedTargets: Set<CompilerTarget>
        if let metadataIndexingResult {
            selectedTargets = metadataIndexingResult.context.targets
        } else if parsingOptions.parseContextualKeyword,
                  let selected = orderedTargets.first(where: { $0.environment == .native }) ?? orderedTargets.first {
            selectedTargets = [selected]
        } else {
            selectedTargets = textBasedStub.targets
        }
        
        let symbolTargets = textBasedStub.swiftSymbolTargets.compactMapValues { targets -> Set<CompilerTarget>? in
            let coverage = targets.intersection(selectedTargets)
            return coverage.isEmpty ? nil : coverage
        }
        
        // Index exported symbols
        let context = IndexingContext(
            moduleName: textBasedStub.moduleName,
            targets: selectedTargets
        )
        var store = SymbolIndexStore()
        try await mergeMangledSymbols(
            symbolTargets,
            context: context,
            location: input.expandingTildeInPath,
            into: &store
        )
        
        // Merge supplemental evidence
        if let metadataIndexingResult {
            try store.merge(metadataIndexingResult)
        }
        if parsingOptions.parseContextualKeyword, let selected = selectedTargets.first, selectedTargets.count == 1 {
            let configuration = try DeclarationModifierConfigurationResolver.resolve(
                targetTriple: compilerTriple(selected), sdkPath: nil
            )
            let source = DeclarationModifierSource(configuration: configuration, context: context)
            try await store.ingest(source)
        }
        
        // Export
        let writer = SwiftInterfaceWriter(configuration: .init(moduleName: context.moduleName))
        let interface = try await writer.write(store)
        writeDiagnostics(interface.diagnostics)
        if let output {
            let outputURL = URL(fileURLWithPath: output.expandingTildeInPath)
            try interface.text.write(to: outputURL, atomically: true, encoding: .utf8)
        } else {
            FileHandle.standardOutput.write(Data(interface.text.utf8))
        }
    }
}

extension SwiftInterfaceCommand {
    struct ParsingOptions: ParsableArguments {
        @Flag(help: "Try to recover opaque type conformances from MachO images.")
        var parseOpaqueReturnType = false

        @Flag(help: "Recover contextual keywords from SDK Swift modules and selected image metadata.")
        var parseContextualKeyword = false
    }

    struct MachOInputOptions: ParsableArguments {
        @Flag(help: "Use the current system dyld shared cache for metadata recovery.")
        var usesDyldSharedCache = false

        @Option(help: "A Mach-O file to parse for metadata recovery.")
        var imagePath: String?
    }
}

fileprivate extension SwiftInterfaceCommand {
    func compilerTriple(_ target: CompilerTarget) -> String {
        let operatingSystem = target.platform == .macOS ? "macosx" : target.platform.rawValue
        let suffix: String
        switch target.environment {
            case .native: suffix = ""
            case .simulator: suffix = "-simulator"
            case .macCatalyst: suffix = "-macabi"
        }
        return target.architecture.rawValue + "-apple-" + operatingSystem + suffix
    }
    
    func mergeMangledSymbols(
        _ symbolTargets: [String: Set<CompilerTarget>],
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
