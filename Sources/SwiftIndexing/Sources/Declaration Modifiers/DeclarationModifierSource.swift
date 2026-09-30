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
        func visit(_ node: Document.Node, path: String, indirectOwner: Bool, ownerKind: SymbolDeclaration.Kind?) throws {
            try Task.checkCancellation()
            let attributes = Set(node.declAttributes ?? [])
            let isEnum = node.declKind == "Enum"
            let isCase = node.declKind == "EnumElement"
            if let expectedKind = node.declarationKind, let mangledName = node.mangledName {
                do {
                    let symbol = isCase ? mangledName + "WC" : mangledName
                    let extracted = try MangledSymbolSource(exportedSymbols: [symbol], context: context).parse()
                    guard let declaration = extracted.declarations.last(where: { $0.kind == expectedKind && $0.evidence == .direct }) else {
                        throw ReadError.invalidDeclaration
                    }
                    let subject = SymbolEvidenceSubject.declaration(declaration.id)
                    for modifier in DeclarationModifier.allCases where modifier.supports(declaration, ownerKind: ownerKind) {
                        guard let isPresent = node.isPresent(modifier) else { continue }
                        evidence.append(.init(source: source, subject: subject,
                                              fact: .modifier(name: modifier.rawValue, isPresent: isPresent), location: path))
                    }
                    if expectedKind == .class {
                        if node.superclassUsr == nil || node.superclassNames?.first != nil {
                            evidence.append(.init(source: source, subject: subject,
                                                  fact: .superclass(typeName: node.superclassNames?.first), location: path))
                        } else {
                            diagnostics.append(.init(kind: .incompleteDeclaration,
                                message: "Compiler superclass spelling is unavailable.", mangledSymbols: [mangledName],
                                declarationID: nil, severity: .warning))
                        }
                    }
                    if expectedKind == .property, let ownership = node.ownership, (1...3).contains(ownership) {
                        evidence.append(.init(source: source, subject: subject,
                                              fact: .storedProperty(isMutable: node.isLet != true), location: path))
                    }
                    if let ownership = node.ownership, !(0...3).contains(ownership) {
                        diagnostics.append(.init(kind: .incompleteDeclaration,
                                                 message: "Unknown compiler reference ownership: \(ownership).", mangledSymbols: [mangledName],
                                                 declarationID: nil, severity: .warning))
                    }
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
                          ownerKind: node.declarationKind)
            }
        }
        try visit(root, path: "/ABIRoot", indirectOwner: false, ownerKind: nil)
        return .init(source: source, context: context, diagnostics: diagnostics, evidence: evidence)
    }

    private static func hasEnumPayload(_ node: DemangledNode) -> Bool {
        if node.kind == .functionType {
            return node.children.first(where: { $0.kind == .returnType })?.children.first?.children.first?.kind == .functionType
        }
        return node.children.contains(where: hasEnumPayload)
    }

    private struct Document: Decodable {
        let ABIRoot: Node

        struct Node: Decodable {
            let kind: String
            let name: String?
            let declKind: String?
            let mangledName: String?
            let declAttributes: [String]?
            let children: [Node]?
            let isOpen: Bool?
            let isLet: Bool?
            let ownership: Int?
            let initializerKind: String?
            let functionSelfKind: String?
            let superclassUsr: String?
            let superclassNames: [String]?

            private enum CodingKeys: String, CodingKey {
                case kind, name, declKind, mangledName, declAttributes, children, isOpen, isLet, ownership
                case superclassUsr, superclassNames
                case initializerKind = "init_kind"
                case functionSelfKind = "funcSelfKind"
            }

            var declarationKind: SymbolDeclaration.Kind? {
                switch declKind {
                    case "Class": return .class
                    case "Struct": return .structure
                    case "Enum": return .enumeration
                    case "Protocol": return .protocol
                    case "Func": return .function
                    case "Var": return .property
                    case "Subscript": return .subscript
                    case "Constructor": return .initializer
                    case "EnumElement": return .enumCase
                    default: return nil
                }
            }

            func isPresent(_ modifier: DeclarationModifier) -> Bool? {
                let attributes = Set(declAttributes ?? [])
                switch modifier {
                    case .final: return attributes.contains("Final")
                    case .indirect: return attributes.contains("Indirect")
                    case .open: return isOpen == true
                    case .required: return attributes.contains("Required")
                    case .override: return attributes.contains("Override")
                    case .lazy: return attributes.contains("Lazy")
                    case .dynamic: return attributes.contains("Dynamic")
                    case .convenience:
                        switch initializerKind {
                            case "Convenience", "ConvenienceFactory": return true
                            case "Designated", "Factory": return false
                            default: return nil
                        }
                    case .mutating:
                        switch functionSelfKind {
                            case "Mutating": return true
                            case "NonMutating": return false
                            default: return nil
                        }
                    case .weak, .unowned, .unownedUnsafe:
                        // ReferenceOwnership in swift/AST/Ownership.h and ReferenceStorage.def:
                        // Strong = 0, Weak = 1, Unowned = 2, Unmanaged = 3.
                        let value = ownership ?? 0
                        guard (0...3).contains(value) else { return nil }
                        return value == (modifier == .weak ? 1 : modifier == .unowned ? 2 : 3)
                }
            }
        }
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
