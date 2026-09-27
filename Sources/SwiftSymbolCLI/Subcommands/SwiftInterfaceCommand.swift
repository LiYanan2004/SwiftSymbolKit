import ArgumentParser
import Foundation
import SwiftSymbolIndexStore

struct SwiftInterfaceCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "interface",
        abstract: "Reconstruct a Swift interface from a TBD file.",
        discussion: "Interface generation requires implementations of SymbolStore.merge and SwiftInterfaceWriter.write."
    )

    @Argument(help: "The TBD file path or file/HTTP/HTTPS URL.", transform: { try Self.inputURL($0) })
    var input: URL

    @Option(name: .shortAndLong, help: "Write the interface to this path. Defaults to standard output.")
    var output: String?

    @Option(help: "The module name. Defaults to the TBD file's name.")
    var moduleName: String?

    @Option(help: "The compiler version recorded in the interface header.")
    var compilerVersion = "unknown"

    mutating func run() throws {
        let stub = try TextBasedStub(yaml: String(contentsOf: input, encoding: .utf8))
        let symbols = stub.swiftSymbols
        guard !symbols.isEmpty else {
            throw ValidationError("The TBD file contains no exported Swift symbols.")
        }

        var store = SymbolIndexStore()
        for symbol in symbols {
            let result = try store.merge(symbol)
            writeDiagnostics(result.diagnostics)
        }

        let writer = SwiftInterfaceWriter(config: .init(
            moduleName: moduleName ?? input.deletingPathExtension().lastPathComponent,
            compilerVersion: compilerVersion
        ))
        let interface = try writer.write(store)
        writeDiagnostics(interface.diagnostics)
        if let output {
            try interface.text.write(to: URL(fileURLWithPath: output), atomically: true, encoding: .utf8)
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
        return URL(fileURLWithPath: value)
    }

    func writeDiagnostics(_ diagnostics: [SymbolDiagnostic]) {
        for diagnostic in diagnostics {
            FileHandle.standardError.write(Data("warning: \(diagnostic.message)\n".utf8))
        }
    }
}
