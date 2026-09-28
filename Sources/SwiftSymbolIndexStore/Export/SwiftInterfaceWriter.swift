import SwiftIndexing
import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftBasicFormat

/// Renders the facts recoverable from exported symbols. Validate the result with a
/// Swift compiler before using it as an importable module interface.
public struct SwiftInterfaceWriter {
    public struct Configuration {
        public struct Header {
            public var compilerVersion: String
            public var interfaceFormatVersion: String
            /// Arguments are escaped individually, preserving their order and boundaries.
            public var compilerFlags: [String]

            public init(
                compilerVersion: String,
                interfaceFormatVersion: String = "1.0",
                compilerFlags: [String] = []
            ) {
                self.compilerVersion = compilerVersion
                self.interfaceFormatVersion = interfaceFormatVersion
                self.compilerFlags = compilerFlags
            }
        }

        /// Module name recorded in the header; all declarations in the index are rendered.
        public var moduleName: String
        public var header: Header
        /// Explicit imports; references in mangled signatures do not identify reexports.
        public var imports: [String]

        public init(moduleName: String, header: Header, imports: [String] = []) {
            self.moduleName = moduleName
            self.header = header
            self.imports = imports
        }

        public init(
            moduleName: String,
            compilerVersion: String,
            interfaceFormatVersion: String = "1.0",
            compilerFlags: [String] = [],
            imports: [String] = []
        ) {
            self.init(moduleName: moduleName, header: Header(
                compilerVersion: compilerVersion, interfaceFormatVersion: interfaceFormatVersion,
                compilerFlags: compilerFlags
            ), imports: imports)
        }
    }

    public struct Output {
        public let text: String
        public let diagnostics: [SymbolDiagnostic]
    }

    public enum ConfigurationError: Error, CustomStringConvertible {
        case invalidValue(String)
        case conflictingModuleName(String)

        public var description: String {
            switch self {
            case .invalidValue(let field): return "Invalid interface configuration: \(field)."
            case .conflictingModuleName(let name): return "Compiler flags specify a different module: \(name)."
            }
        }
    }

    public var configuration: Configuration

    public init(configuration: Configuration) {
        self.configuration = configuration
    }

    public func write(_ index: SymbolIndexStore) async throws -> Output {
        try Task.checkCancellation()
        guard index.resolvedFactsBySubject.isEmpty, index.exportAssessmentsByDeclarationID.isEmpty else {
            fatalError("TODO: Render the store's reconciled declarations and facts using its export assessments.")
        }
        let header = try Trivia(pieces: headerLines().flatMap { [.lineComment($0), .newlines(1)] })
        let imports = try Set(configuration.imports).subtracting([configuration.moduleName]).sorted().map { module in
            let components = module.split(separator: ".", omittingEmptySubsequences: false)
            return try ImportDeclSyntax(path: ImportPathComponentListSyntax {
                for (position, component) in components.enumerated() {
                    try ImportPathComponentSyntax(name: InterfaceTypeRenderer.identifier(String(component)),
                        trailingPeriod: position < components.count - 1 ? .periodToken() : nil)
                }
            })
        }
        var renderer = InterfaceDeclarationRenderer(index: index)
        let declarations = try await renderer.render()
        let sourceFile = SourceFileSyntax(leadingTrivia: header,
            endOfFileToken: .endOfFileToken(leadingTrivia: imports.isEmpty && declarations.isEmpty ? [] : .newline)) {
            for importDeclaration in imports {
                importDeclaration.with(\.leadingTrivia, .newline)
            }
            for (position, declaration) in declarations.enumerated() {
                CodeBlockItemSyntax(leadingTrivia: .newlines(imports.isEmpty && position == 0 ? 1 : 2),
                    item: .decl(declaration))
            }
        }
        let text: String
        if sourceFile.statements.count < 2 {
            text = sourceFile.formatted(using: BasicFormat(indentationWidth: .spaces(4))).description
        } else {
            let blocks = try await ParallelMap.map(Array(sourceFile.statements)) {
                // Detach to keep formatting from walking sibling declarations through the parent.
                $0.detached.formatted(using: BasicFormat(indentationWidth: .spaces(4))).description
            }
            text = blocks.joined() + sourceFile.endOfFileToken.description
        }
        try Task.checkCancellation()
        return Output(text: text, diagnostics: index.diagnostics + renderer.diagnostics)
    }
}

fileprivate extension SwiftInterfaceWriter {
    func headerLines() throws -> [String] {
        guard (try? InterfaceTypeRenderer.identifier(configuration.moduleName)) != nil else {
            throw ConfigurationError.invalidValue("moduleName")
        }
        let header = configuration.header
        for (name, value) in [("compilerVersion", header.compilerVersion),
                              ("interfaceFormatVersion", header.interfaceFormatVersion)] {
            guard !value.isEmpty, !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw ConfigurationError.invalidValue(name)
            }
        }
        var flags = header.compilerFlags
        guard !flags.contains(where: { $0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }) else {
            throw ConfigurationError.invalidValue("compilerFlags")
        }
        var hasModuleName = false
        var position = 0
        while position < flags.count {
            let flag = flags[position]
            let name: String?
            if flag == "-module-name" {
                guard position + 1 < flags.count else { throw ConfigurationError.invalidValue("-module-name requires a value") }
                position += 1
                name = flags[position]
            } else if flag.hasPrefix("-module-name=") {
                name = String(flag.dropFirst("-module-name=".count))
            } else {
                name = nil
            }
            if let name {
                guard name == configuration.moduleName else { throw ConfigurationError.conflictingModuleName(name) }
                hasModuleName = true
            }
            position += 1
        }
        if !hasModuleName { flags += ["-module-name", configuration.moduleName] }
        return [
            "// swift-interface-format-version: \(header.interfaceFormatVersion)",
            "// swift-compiler-version: \(header.compilerVersion)",
            "// swift-module-flags: \(flags.map(quotedArgument).joined(separator: " "))",
        ]
    }

    func quotedArgument(_ argument: String) -> String {
        if !argument.isEmpty && !argument.contains(where: { $0.isWhitespace || $0 == "\"" || $0 == "'" || $0 == "\\" }) {
            return argument
        }
        return "\"" + argument.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
