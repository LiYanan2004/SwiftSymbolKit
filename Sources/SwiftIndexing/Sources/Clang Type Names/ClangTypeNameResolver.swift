import Foundation

/// Discovers Swift spellings in explicitly supplied imports and verifies them with
/// the selected compiler. Tool execution is separate from index mutation and rendering.
/// All generated graphs, probes, SIL and diagnostics are retained in outputDirectory.
public struct ClangTypeNameResolver: Sendable {
    public struct Configuration: Sendable {
        public let toolchainDirectory: String
        public let sdkPath: String
        public let targetTriple: String
        public let swiftLanguageVersion: String
        public let importSearchPaths: [String]
        public let frameworkSearchPaths: [String]
        public let clangArguments: [String]

        public init(toolchainDirectory: String, sdkPath: String, targetTriple: String,
                    swiftLanguageVersion: String = "5", importSearchPaths: [String] = [],
                    frameworkSearchPaths: [String] = [], clangArguments: [String] = []) {
            self.toolchainDirectory = toolchainDirectory
            self.sdkPath = sdkPath
            self.targetTriple = targetTriple
            self.swiftLanguageVersion = swiftLanguageVersion
            self.importSearchPaths = importSearchPaths
            self.frameworkSearchPaths = frameworkSearchPaths
            self.clangArguments = clangArguments
        }

        fileprivate var arguments: [String] {
            ["-sdk", sdkPath, "-target", targetTriple, "-swift-version", swiftLanguageVersion]
                + importSearchPaths.flatMap { ["-I", $0] }
                + frameworkSearchPaths.flatMap { ["-F", $0] }
                + clangArguments.flatMap { ["-Xcc", $0] }
        }
    }

    public enum ResolutionError: Error, Equatable {
        case incompatibleContext
        case outputDirectoryExists(String)
        case invalidSymbolGraph(String)
        case unsupportedName(String)
        case toolFailed(tool: String, status: Int32, diagnosticsPath: String)
    }

    public let configuration: Configuration

    public init(configuration: Configuration) { self.configuration = configuration }

    /// Runs synchronously. Imported modules are caller input; import discovery is independent.
    /// One compiler target must cover the entire result context.
    public func resolve(_ identities: Set<ClangTypeIdentity>, importedModules: Set<String>,
                        context: IndexingContext, outputDirectory: URL) throws -> IndexingResult {
        guard context.isValid,
              context.targets == [try IndexingTarget(parsing: configuration.targetTriple)] else {
            throw ResolutionError.incompatibleContext
        }
        for module in importedModules {
            _ = try ClangTypeNameCandidates.sourcePath(module.split(separator: ".", omittingEmptySubsequences: false).map(String.init))
        }
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: outputDirectory.path) else {
            throw ResolutionError.outputDirectoryExists(outputDirectory.path)
        }
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let compilerVersion = try invoke("swiftc", arguments: ["--version"],
                                         output: outputDirectory.appendingPathComponent("compiler.txt")).output
        let producerData = try JSONEncoder().encode([configuration.toolchainDirectory, compilerVersion] + configuration.arguments)
        let source = SymbolEvidenceSource(kind: .compilerDump, location: outputDirectory.path,
            artifactIdentifier: outputDirectory.path, lineageIdentifier: outputDirectory.path,
            producer: String(decoding: producerData, as: UTF8.self))
        let common = configuration.arguments + ["-module-cache-path", outputDirectory.appendingPathComponent("module-cache").path]
        var candidates = Set<ClangTypeNameCandidates.Candidate>()
        if !identities.isEmpty {
            for (position, module) in importedModules.sorted().enumerated() {
                try Task.checkCancellation()
                let graphDirectory = outputDirectory.appendingPathComponent("graph-\(position)")
                try fileManager.createDirectory(at: graphDirectory, withIntermediateDirectories: false)
                _ = try invoke("swift-symbolgraph-extract", arguments: common + ["-module-name", module,
                    "-output-dir", graphDirectory.path], output: graphDirectory.appendingPathComponent("extract.txt"))
                // Extension graphs describe a different owner and are deliberately excluded.
                let graph = try Data(contentsOf: graphDirectory.appendingPathComponent("\(module).symbols.json"))
                candidates.formUnion(try ClangTypeNameCandidates.read(graph, moduleName: module,
                    requestedNames: Set(identities.map(\.name))))
            }
        }
        var verified: [ClangTypeIdentity: [ClangTypeName]] = [:]
        var diagnostics: [SymbolDiagnostic] = []
        let sortedCandidates = candidates.sorted {
            [$0.swiftName.qualifiedName, $0.clangUSR, $0.declarationKind]
                .lexicographicallyPrecedes([$1.swiftName.qualifiedName, $1.clangUSR, $1.declarationKind])
        }
        for (position, candidate) in sortedCandidates.enumerated() {
            try Task.checkCancellation()
            let probeURL = outputDirectory.appendingPathComponent("Probe-\(position).swift")
            do {
                let importName = try ClangTypeNameCandidates.sourcePath(candidate.requiredImport.split(separator: ".").map(String.init))
                let spelling = try ClangTypeNameCandidates.sourcePath([candidate.swiftName.moduleName] + candidate.swiftName.pathComponents)
                let parameter = (candidate.declarationKind == "swift.protocol" ? "any " : "") + spelling
                try "import \(importName)\npublic func resolve(_ value: \(parameter)) {}\n"
                    .write(to: probeURL, atomically: true, encoding: .utf8)
                let result = try invoke("swiftc", arguments: common + ["-emit-silgen", "-module-name", "ClangNameProbe", probeURL.path],
                    output: outputDirectory.appendingPathComponent("probe-\(position).sil"), allowFailure: true)
                let symbols = Self.probeSymbols(in: result.output)
                guard result.status == 0, symbols.count == 1,
                      let identity = ClangTypeIdentity.probeIdentity(mangledSymbol: symbols[0]),
                      identities.contains(identity) else {
                    diagnostics.append(Self.diagnostic("Candidate \(candidate.swiftName.qualifiedName) did not verify a requested ABI identity; see \(probeURL.path)."))
                    continue
                }
                verified[identity, default: []].append(.init(identity: identity, swiftName: candidate.swiftName,
                    requiredImport: candidate.requiredImport, clangUSR: candidate.clangUSR,
                    declarationKind: candidate.declarationKind, probeSymbol: symbols[0]))
            } catch ResolutionError.unsupportedName(let name) {
                diagnostics.append(Self.diagnostic("Unsupported candidate name: \(name)"))
            }
        }
        let evidence = identities.sorted { [$0.kind.rawValue, $0.name].lexicographicallyPrecedes([$1.kind.rawValue, $1.name]) }.map { identity in
            let resolution = ClangTypeNameResolution(identity: identity, candidates: verified[identity] ?? [])
            if resolution.status != .resolved {
                diagnostics.append(Self.diagnostic("\(resolution.status) Clang type: \(identity.kind.rawValue):\(identity.name)"))
            }
            return SymbolEvidence(source: source, subject: .module(context.moduleName), fact: .clangTypeName(resolution),
                                  location: outputDirectory.path)
        }
        return IndexingResult(source: source, context: context, diagnostics: diagnostics, evidence: evidence)
    }

    private static func diagnostic(_ message: String) -> SymbolDiagnostic {
        .init(kind: .incompleteDeclaration, message: message, mangledSymbols: [], declarationID: nil, severity: .warning)
    }

    private static func probeSymbols(in sil: String) -> [String] {
        sil.split(separator: "\n").compactMap { line in
            guard line.hasPrefix("sil "), let start = line.range(of: "@$s"),
                  let end = line[start.upperBound...].range(of: " :") else { return nil }
            return String(line[line.index(after: start.lowerBound)..<end.lowerBound])
        }
    }

    private func invoke(_ tool: String, arguments: [String], output: URL,
                        allowFailure: Bool = false) throws -> (output: String, status: Int32) {
        try Task.checkCancellation()
        let executable = URL(fileURLWithPath: configuration.toolchainDirectory).appendingPathComponent(tool)
        let diagnosticsURL = output.appendingPathExtension("stderr")
        try Data().write(to: output)
        try Data().write(to: diagnosticsURL)
        let standardOutput = try FileHandle(forWritingTo: output)
        let standardError = try FileHandle(forWritingTo: diagnosticsURL)
        defer { try? standardOutput.close(); try? standardError.close() }
        let commandData = try JSONEncoder().encode([executable.path] + arguments)
        try commandData.write(to: output.appendingPathExtension("command.json"))
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = standardOutput
        process.standardError = standardError
        try process.run()
        process.waitUntilExit()
        try Task.checkCancellation()
        guard process.terminationStatus == 0 || allowFailure else {
            throw ResolutionError.toolFailed(tool: tool, status: process.terminationStatus, diagnosticsPath: diagnosticsURL.path)
        }
        return (try String(contentsOf: output, encoding: .utf8), process.terminationStatus)
    }
}
