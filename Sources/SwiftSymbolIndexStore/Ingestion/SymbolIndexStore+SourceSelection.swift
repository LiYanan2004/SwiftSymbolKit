import Foundation
import SwiftIndexing

extension SymbolIndexStore {
    /// Convenience input selection for indexing clients.
    /// File readers extract their own context and only the requested information.
    public enum Source: Sendable {
        /// All supplied symbols cover the targets specified by the context.
        case mangledSymbols([String], context: IndexingContext)
        case swiftInterface(URL, requestedInformation: Set<SupplementalInformation>)
        case dyldSharedCache(URL, imageInstallName: String, requestedInformation: Set<SupplementalInformation>)
        /// Reads opaque and enum case metadata from a Mach-O file without executing it.
        case loadedImage(path: String, descriptorSymbols: [String], context: IndexingContext, enumDescriptorSymbols: [String] = [])
        /// A captured dump, including its tool version and invocation for provenance.
        case compilerDump(URL, producer: String, requestedInformation: Set<SupplementalInformation>)
        case declarationModifiers(DeclarationModifierSource.Configuration, context: IndexingContext)
    }

    /// A failed read leaves this source unapplied; preceding sources remain indexed.
    /// Sources are processed in the supplied order, with cooperative cancellation.
    public mutating func ingest(sources: [Source]) async throws {
        try Task.checkCancellation()
        for source in sources {
            try Task.checkCancellation()
            try await ingest(source)
        }
    }

    @discardableResult
    public mutating func ingest(_ source: Source) async throws -> MergeResult {
        try Task.checkCancellation()
        return try await ingest(reader(for: source))
    }
}

fileprivate extension SymbolIndexStore {
    func reader(for source: Source) -> any IndexingSource {
        switch source {
        case .mangledSymbols(let symbols, let context):
            return MangledSymbolSource(exportedSymbols: symbols, context: context)
        case .swiftInterface(let url, let requestedInformation):
            return SwiftInterfaceSource(location: url.path, requestedInformation: requestedInformation)
        case .dyldSharedCache(let url, let imageInstallName, let requestedInformation):
            return DyldSharedCacheSource(location: url.path, imageInstallName: imageInstallName, requestedInformation: requestedInformation)
        case .loadedImage(let path, let symbols, let context, let enumSymbols):
            return LoadedImageSource(imagePath: path, descriptorSymbols: symbols, context: context, enumDescriptorSymbols: enumSymbols)
        case .compilerDump(let url, let producer, let requestedInformation):
            return CompilerDumpSource(location: url.path, producer: producer, requestedInformation: requestedInformation)
        case .declarationModifiers(let configuration, let context):
            return DeclarationModifierSource(configuration: configuration, context: context)
        }
    }
}
