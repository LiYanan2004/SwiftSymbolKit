import Foundation
import Testing
import SwiftIndexing
@testable import SwiftSymbolIndexStore

struct OpaqueRecoveryTests {
    @Test func recoversCompilerGeneratedDescriptors() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = directory.appendingPathComponent("libOpaqueFixtures.dylib")
        _ = try run(["swiftc", OpaqueRecoveryFixture.sourceURL.path, "-module-name", "OpaqueFixtures",
            "-enable-library-evolution", "-emit-library", "-o", library.path,
            "-module-cache-path", directory.appendingPathComponent("ModuleCache").path])
        let symbols = try run(["nm", "-gUj", library.path]).split(separator: "\n").map(String.init).filter { $0.hasPrefix("_$s") }
        #if arch(arm64)
        let target = IndexingTarget(architecture: .arm64, platform: .macOS)
        #else
        let target = IndexingTarget(architecture: .x86_64, platform: .macOS)
        #endif
        let context = IndexingContext(moduleName: "OpaqueFixtures", targets: [target])
        let source = LoadedImageSource(imagePath: library.path,
            descriptorSymbols: symbols.filter { $0.hasSuffix("QOMQ") }, context: context)
        let indexingResult = try await source.read()
        #expect(indexingResult.exportedSymbols.isEmpty)
        #expect(!indexingResult.diagnostics.contains { $0.severity == .warning }, "\(indexingResult.diagnostics.map(\.message))")
        var index = SymbolIndexStore()
        try await index.ingest(MangledSymbolSource(exportedSymbols: symbols, context: context))
        let originalExports = index.exportedSymbols
        try index.merge(indexingResult)
        #expect(index.exportedSymbols == originalExports)
        let writer = SwiftInterfaceWriter(configuration: .init(moduleName: "OpaqueFixtures", compilerVersion: "test"))
        let output = try await writer.write(index)
        #expect(!output.diagnostics.contains { $0.severity == .error }, "\(output.diagnostics.map(\.message))")
        let normalized = output.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        for fixture in OpaqueRecoveryFixture.allCases {
            let declaration = try #require(index.declarationsByID.values.first { $0.name == fixture.rawValue })
            let recovered = (index.resolvedFactsBySubject[.declaration(declaration.id)] ?? []).compactMap { fact -> OpaqueReturnType? in
                if case .opaqueReturnType(let type) = fact.fact { return type }
                return nil
            }
            #expect(recovered.count == (fixture == .multiple ? 2 : 1), "\(fixture)")
            #expect(recovered.allSatisfy { $0.parameterDepth == fixture.expectedDepth }, "\(fixture)")
            #expect(recovered.allSatisfy { $0.underlyingType != nil }, "\(fixture)")
            #expect(normalized.contains(fixture.expectedFragment), "\(fixture): \(output.text)")
            if fixture == .sequence { #expect(recovered.first?.sameTypeRequirements.isEmpty == false) }
            if fixture == .simple { #expect(recovered.first?.underlyingType?.description == "OpaqueFixtures.Payload") }
        }
        // Repeated ingestion is idempotent; metadata does not grant exports.
        let evidenceCount = index.evidence.count
        try index.merge(indexingResult)
        #expect(index.evidence.count == evidenceCount)
        #expect(try await writer.write(index).text == output.text)

        let missing = try await LoadedImageSource(imagePath: library.path,
            descriptorSymbols: ["_$s14OpaqueFixtures7missingQryFQOMQ"], context: context).read()
        #expect(missing.observations.isEmpty)
        #expect(missing.diagnostics.contains { $0.severity == .warning })

        let otherTarget = IndexingTarget(architecture: target.architecture == .arm64 ? .x86_64 : .arm64, platform: .macOS)
        let foreignDescriptor = "_$s14OpaqueFixtures7missingQryFQOMQ"
        var coverage = Dictionary(uniqueKeysWithValues: source.descriptorSymbols.map { ($0, Set([target, otherTarget])) })
        coverage[foreignDescriptor] = [otherTarget]
        let automatic = try await LoadedImageSource(imagePath: library.path,
            descriptorSymbols: Array(coverage.keys),
            context: .init(moduleName: context.moduleName, targets: [target, otherTarget]),
            descriptorSymbolTargets: coverage).read()
        #expect(automatic.context.targets == [target])
        #expect(automatic.observations.count == indexingResult.observations.count)
        #expect(!automatic.diagnostics.contains { $0.mangledSymbols.contains(foreignDescriptor) })
        await #expect(throws: (any Error).self) {
            try await LoadedImageSource(imagePath: library.path, descriptorSymbols: source.descriptorSymbols,
                context: .init(moduleName: context.moduleName, targets: [otherTarget]),
                descriptorSymbolTargets: Dictionary(uniqueKeysWithValues: source.descriptorSymbols.map { ($0, Set([otherTarget])) })).read()
        }
        let mismatched = try await LoadedImageSource(imagePath: library.path, descriptorSymbols: source.descriptorSymbols,
            context: .init(moduleName: context.moduleName, targets: [otherTarget])).read()
        #expect(mismatched.observations.isEmpty)
        #expect(mismatched.diagnostics.count == source.descriptorSymbols.count)

        let simple = try #require(index.declarationsByID.values.first { $0.name == "simple" })
        let observation = try #require(indexingResult.observations.first {
            if case .mangledSymbol(let name) = $0.subject { return name.contains("6simple") }
            return false
        })
        let different = OpaqueReturnType(ordinal: 0, parameterDepth: 0, constraints: [])
        let conflict = IndexingResult(source: .init(kind: .loadedImage, location: "another-image",
            artifactIdentifier: "another-uuid", lineageIdentifier: "another-build"), context: context,
            observations: [.init(subject: observation.subject, fact: .opaqueReturnType(different), location: observation.location)])
        try index.merge(conflict)
        #expect(index.resolvedFactsBySubject[.declaration(simple.id)]?.isEmpty == true)
        #expect(index.diagnostics.contains { $0.kind == .conflictingInformation })
        #expect(index.exportedSymbols == originalExports)
        let conflictedText = try await writer.write(index).text
        #expect(!conflictedText.contains("func simple() -> some OpaqueFixtures.P"))

        var reversed = SymbolIndexStore()
        try await reversed.ingest(MangledSymbolSource(exportedSymbols: symbols, context: context))
        try reversed.merge(conflict)
        try reversed.merge(indexingResult)
        #expect(try await writer.write(reversed).text == conflictedText)
    }

    private func run(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else { throw CommandError(output: text) }
        return text
    }

    private struct CommandError: Error { let output: String }
}
