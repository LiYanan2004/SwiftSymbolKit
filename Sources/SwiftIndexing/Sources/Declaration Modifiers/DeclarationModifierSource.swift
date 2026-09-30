import CryptoKit
import Foundation
import SwiftDemangle

/// Reads compiler semantics without admitting declarations into the export surface.
public struct DeclarationModifierSource: IndexingSource {
    public struct Configuration: Sendable {
        public let sdkPath: String
        public let targetTriple: String
        public let toolchainDirectory: String?
        public let importSearchPaths: [String]
        public let frameworkSearchPaths: [String]

        public init(sdkPath: String, targetTriple: String, toolchainDirectory: String? = nil,
                    importSearchPaths: [String] = [], frameworkSearchPaths: [String] = []) {
            self.sdkPath = sdkPath
            self.targetTriple = targetTriple
            self.toolchainDirectory = toolchainDirectory
            self.importSearchPaths = importSearchPaths
            self.frameworkSearchPaths = frameworkSearchPaths
        }
    }

    public let configuration: Configuration
    public let context: IndexingContext

    public init(configuration: Configuration, context: IndexingContext) {
        self.configuration = configuration
        self.context = context
    }

    public func read() async throws -> IndexingResult {
        guard context.isValid, context.targets == [try CompilerTarget(parsing: configuration.targetTriple)] else {
            throw IndexingSourceError.invalidContext
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("api.json")
        let arguments = ["-dump-sdk", "-abort-on-module-fail", "-module", context.moduleName,
                         "-sdk", configuration.sdkPath, "-target", configuration.targetTriple]
            + configuration.importSearchPaths.flatMap { ["-I", $0] }
            + configuration.frameworkSearchPaths.flatMap { ["-F", $0] }
        let compilerVersion = try invoke("swiftc", arguments: ["--version"], directory: directory)
        _ = try invoke("swift-api-digester", arguments: arguments + ["-o", output.path], directory: directory)
        let data = try Data(contentsOf: output)
        let producer = String(decoding: try JSONEncoder().encode(
            [configuration.toolchainDirectory ?? "xcrun", compilerVersion] + arguments), as: UTF8.self)
        let source = SymbolEvidenceSource(kind: .compilerDump, location: configuration.sdkPath,
            artifactIdentifier: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            lineageIdentifier: configuration.sdkPath + ":" + context.moduleName + ":" + configuration.targetTriple,
            producer: producer)
        return try Self.parse(data, source: source, context: context)
    }

    /// Supports captured digester output as well as live compiler invocations.
    public static func parse(_ data: Data, source: SymbolEvidenceSource, context: IndexingContext) throws -> IndexingResult {
        guard source.kind == .compilerDump, source.producer != nil, context.isValid, context.targets.count == 1 else {
            throw IndexingSourceError.invalidContext
        }
        let root = try JSONDecoder().decode(Document.self, from: data).ABIRoot
        guard root.kind == "Root", root.name == context.moduleName else { throw ReadError.invalidModule }
        var evidence: [SymbolEvidence] = []
        var diagnostics: [SymbolDiagnostic] = []
        func visit(_ node: Node, path: String, indirectOwner: Bool, classOwner: Bool) throws {
            try Task.checkCancellation()
            let attributes = Set(node.declAttributes ?? [])
            let isEnum = node.declKind == "Enum"
            let isClass = node.declKind == "Class"
            let isCase = node.declKind == "EnumElement"
            let supportsFinal = isClass || (classOwner && ["Func", "Var", "Subscript"].contains(node.declKind ?? ""))
            if isEnum || isCase || supportsFinal, let mangledName = node.mangledName {
                do {
                    let symbol = isCase ? mangledName + "WC" : mangledName
                    let extracted = try MangledSymbolSource(exportedSymbols: [symbol], context: context).parse()
                    let expectedKind: SymbolDeclaration.Kind = isEnum ? .enumeration : isCase ? .enumCase : isClass ? .class
                        : node.declKind == "Var" ? .property : node.declKind == "Subscript" ? .subscript : .function
                    guard let declaration = extracted.declarations.last(where: { $0.kind == expectedKind && $0.evidence == .direct }) else {
                        throw ReadError.invalidDeclaration
                    }
                    let subject = SymbolEvidenceSubject.declaration(declaration.id)
                    evidence.append(.init(source: source, subject: subject,
                        fact: .modifier(name: supportsFinal ? "final" : "indirect",
                                        isPresent: attributes.contains(supportsFinal ? "Final" : "Indirect")), location: path))
                    if isCase {
                        let hasPayload = declaration.signature.map(Self.hasEnumPayload) ?? false
                        evidence.append(.init(source: source, subject: subject,
                            fact: .enumCaseIndirectStorage(isIndirect: hasPayload && (indirectOwner || attributes.contains("Indirect"))),
                            location: path))
                    }
                } catch is CancellationError { throw CancellationError() }
                catch {
                    diagnostics.append(.init(kind: .incompleteDeclaration,
                        message: "Declaration modifier recovery: \(error)", mangledSymbols: [mangledName],
                        declarationID: nil, severity: .warning))
                }
            }
            for (position, child) in (node.children ?? []).enumerated() {
                try visit(child, path: path + "/children/\(position)",
                          indirectOwner: isEnum && attributes.contains("Indirect"),
                          classOwner: isClass)
            }
        }
        try visit(root, path: "/ABIRoot", indirectOwner: false, classOwner: false)
        return .init(source: source, context: context, diagnostics: diagnostics, evidence: evidence)
    }

    private static func hasEnumPayload(_ node: DemangledNode) -> Bool {
        if node.kind == .functionType {
            return node.children.first(where: { $0.kind == .returnType })?.children.first?.children.first?.kind == .functionType
        }
        return node.children.contains(where: hasEnumPayload)
    }

    private struct Document: Decodable { let ABIRoot: Node }
    private struct Node: Decodable {
        let kind: String
        let name: String?
        let declKind: String?
        let mangledName: String?
        let declAttributes: [String]?
        let children: [Node]?
    }

    public enum ReadError: Error {
        case invalidModule
        case invalidDeclaration
        case toolFailed(tool: String, status: Int32, diagnostics: String)
    }

    private func invoke(_ tool: String, arguments: [String], directory: URL) throws -> String {
        try Task.checkCancellation()
        let output = directory.appendingPathComponent(tool + ".log")
        _ = FileManager.default.createFile(atPath: output.path, contents: nil)
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close() }
        let process = Process()
        if let toolchainDirectory = configuration.toolchainDirectory {
            process.executableURL = URL(fileURLWithPath: toolchainDirectory).appendingPathComponent("usr/bin/" + tool)
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = [tool] + arguments
        }
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        process.waitUntilExit()
        try Task.checkCancellation()
        let text = try String(contentsOf: output, encoding: .utf8)
        guard process.terminationStatus == 0 else {
            throw ReadError.toolFailed(tool: tool, status: process.terminationStatus, diagnostics: text)
        }
        return text
    }
}
