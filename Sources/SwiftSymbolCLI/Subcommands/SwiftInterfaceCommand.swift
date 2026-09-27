import ArgumentParser
import Foundation
import OSLog
import SwiftSymbolIndexStore

struct SwiftInterfaceCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "interface",
        abstract: "Reconstruct a Swift interface from a TBD file.",
        discussion: "Reconstructs declarations recoverable from exported symbols. Validate the output with a Swift compiler before importing it."
    )

    @Argument(
        help: "The TBD file path or file/HTTP/HTTPS URL.",
        transform: { try Self.inputURL($0) }
    )
    var input: URL

    @Option(name: .shortAndLong, help: "Write the interface to this path. Defaults to standard output.")
    var output: String?

    @Option(help: "The module name recorded in the header. All indexed declarations are included. Defaults to the TBD file's name.")
    var moduleName: String?

    @Option(help: "The compiler version recorded in the interface header.")
    var compilerVersion = "unknown"

    @Option(help: "The interface format version recorded in the header.")
    var interfaceFormatVersion = "1.0"

    @Option(help: "The compiler target triple recorded in module flags.")
    var target: String?

    @Option(help: "The Swift language version recorded in module flags.")
    var swiftVersion: String?

    @Flag(help: "Record -enable-library-evolution in module flags.")
    var enableLibraryEvolution = false

    @Option(name: .customLong("import"), help: "A module to import. Repeat for additional modules.")
    var imports: [String] = []

    @Option(
        name: .customLong("compiler-flag"),
        parsing: .unconditionalSingleValue,
        help: "An additional compiler argument. Repeat for each argument, including flag values."
    )
    var otherCompilerFlags: [String] = []

    mutating func run() throws {
        let stub = try TextBasedStub(yaml: String(contentsOf: input, encoding: .utf8))
        let symbols = stub.swiftSymbols
        guard !symbols.isEmpty else {
            throw ValidationError("The TBD file contains no exported Swift symbols.")
        }

        var store = SymbolIndexStore()
        do {
            try store.merge(contentsOf: symbols)
        } catch let error as SymbolIndexStore.MergeError {
            Loggers.symbolExtraction.error("Failed to parse symbol: \(String(describing: error.underlyingError), privacy: .public). Symbol: \(error.mangledSymbol, privacy: .public)")
            throw error.underlyingError
        }

        var compilerFlags: [String] = []
        if let target {
            compilerFlags += ["-target", target]
        }
        if let swiftVersion {
            compilerFlags += ["-swift-version", swiftVersion]
        }
        if enableLibraryEvolution {
            compilerFlags.append("-enable-library-evolution")
        }
        compilerFlags += otherCompilerFlags

        let writer = SwiftInterfaceWriter(configuration: .init(
            moduleName: moduleName ?? input.deletingPathExtension().lastPathComponent,
            header: .init(compilerVersion: compilerVersion, interfaceFormatVersion: interfaceFormatVersion,
                          compilerFlags: compilerFlags),
            imports: imports
        ))
        let interface = try writer.write(store)
        writeDiagnostics(interface.diagnostics)
        if let output {
            try interface.text.write(
                to: URL(filePath: output.expandingTildeInPath),
                atomically: true,
                encoding: .utf8
            )
        } else {
            FileHandle.standardOutput.write(Data(interface.text.utf8))
        }
    }
}

fileprivate extension SwiftInterfaceCommand {
    static func inputURL(_ value: String) throws -> URL {
        if let url = URL(string: value), let scheme = url.scheme {
            guard ["file", "http", "https"].contains(scheme.lowercased()) else {
                throw ValidationError("Expected a file, HTTP or HTTPS URL.")
            }
            return url
        }
        return URL(filePath: value.expandingTildeInPath)
    }

    func writeDiagnostics(_ diagnostics: [SymbolDiagnostic]) {
        for diagnostic in diagnostics {
            let logger: Logger
            switch diagnostic.kind {
                case .unsupportedSymbol: logger = Loggers.symbolExtraction
                case .conflictingInformation: logger = Loggers.symbolMerging
                case .incompleteDeclaration: logger = Loggers.interfaceGeneration
            }
            switch diagnostic.severity {
                case .info: logger.info("\(diagnostic.message, privacy: .public)")
                case .warning: logger.warning("\(diagnostic.message, privacy: .public)")
                case .error: logger.error("\(diagnostic.message, privacy: .public)")
            }
        }
    }
}

fileprivate extension String {
    var expandingTildeInPath: String {
        (self as NSString).expandingTildeInPath
    }
}
