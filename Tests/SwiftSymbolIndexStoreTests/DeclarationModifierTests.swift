import Foundation
import MachOKit
import Testing
import SwiftIndexing
import SwiftParser
import SwiftSyntax
@testable import SwiftSymbolIndexStore

struct DeclarationModifierTests {
    private let fixture = """
    public final class FinalClass {
        public init() {}
        public func method() {}
    }
    public class ExtensibleClass {
        public init() {}
        public final func finalMethod() {}
        public func ordinaryMethod() {}
        public final var property: Int { 1 }
        public final subscript(index: Int) -> Int { index }
    }
    public enum MixedEnum {
        case value(Int)
        indirect case boxed(Int)
        indirect case recursive(MixedEnum)
        case empty
    }
    public indirect enum IndirectEnum {
        case empty
        case value(Int)
        case recursive(IndirectEnum)
    }
    public enum GenericEnum<Element> {
        case value(Element)
        indirect case recursive(GenericEnum<Element>)
    }
    public func opaqueValue() -> some Equatable { 1 }
    """

    @Test func recoversAndVerifiesCompilerSemantics() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("Fixture.swift")
        try fixture.write(to: input, atomically: true, encoding: .utf8)
        let library = directory.appendingPathComponent("libModifierFixture.dylib")
        _ = try run(["swiftc", input.path, "-module-name", "ModifierFixture", "-enable-library-evolution",
            "-emit-library", "-emit-module", "-emit-module-path", directory.appendingPathComponent("ModifierFixture.swiftmodule").path,
            "-o", library.path])
        let symbols = try run(["nm", "-gUj", library.path]).split(separator: "\n").map(String.init).filter { $0.hasPrefix("_$s") }
        #if arch(arm64)
        let triple = "arm64-apple-macosx15.0"
        #else
        let triple = "x86_64-apple-macosx15.0"
        #endif
        let context = IndexingContext(moduleName: "ModifierFixture", targets: [try CompilerTarget(parsing: triple)])
        let sdk = try run(["--sdk", "macosx", "--show-sdk-path"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let compiler = try await DeclarationModifierSource(configuration: .init(sdkPath: sdk,
            targetTriple: triple, importSearchPaths: [directory.path]), context: context).read()
        #expect(compiler.exportedSymbols.isEmpty)
        #expect(compiler.diagnostics.isEmpty, "\(compiler.diagnostics.map(\.message))")
        let binary = try await LoadedImageSource(imagePath: library.path,
            descriptorSymbols: symbols.filter { $0.hasSuffix("QOMQ") }, context: context,
            enumDescriptorSymbols: symbols.filter { $0.hasSuffix("OMn") }).read()
        #expect(!MachOImage.images.contains { $0.path == library.path })
        #expect(binary.diagnostics.isEmpty, "\(binary.diagnostics.map(\.message))")
        #expect(binary.evidence.count == 10)
        var store = SymbolIndexStore()
        try await store.ingest(MangledSymbolSource(exportedSymbols: symbols, context: context))
        let exports = store.exportedSymbols
        try store.merge(compiler)
        try store.merge(binary)
        #expect(store.exportedSymbols == exports)
        let writer = SwiftInterfaceWriter(configuration: .init(moduleName: context.moduleName))
        let output = try await writer.write(store)
        #expect(!output.diagnostics.contains { $0.kind == .conflictingInformation }, "\(output.diagnostics.map(\.message))")
        let text = output.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        #expect(text.contains("public final class FinalClass"))
        #expect(text.contains("public class ExtensibleClass"))
        #expect(text.contains("public final func finalMethod"))
        #expect(text.contains("public func ordinaryMethod"))
        #expect(text.contains("public final var property"))
        #expect(text.contains("public final subscript"))
        #expect(text.contains("indirect case boxed"))
        #expect(text.contains("public indirect enum IndirectEnum"))
        let enums = Parser.parse(source: output.text).statements.compactMap {
            $0.item.as(DeclSyntax.self)?.as(EnumDeclSyntax.self)?.description
        }.joined(separator: "\n")
        let enumSource = directory.appendingPathComponent("GeneratedEnums.swift")
        try enums.write(to: enumSource, atomically: true, encoding: .utf8)
        _ = try run(["swiftc", "-typecheck", "-module-name", context.moduleName, enumSource.path])
        let wholeEnum = try #require(store.declarationsByID.values.first { $0.name == "IndirectEnum" && $0.kind == .enumeration })
        let wholeEnumFacts = try #require(store.resolvedFactsBySubject[.declaration(wholeEnum.id)])
        #expect(wholeEnumFacts.contains { $0.fact == .modifier(name: "indirect", isPresent: true) && $0.confidence == .singleSource })
        for member in store.members(of: wholeEnum.id) where member.kind == .enumCase {
            let facts = try #require(store.resolvedFactsBySubject[.declaration(member.id)])
            #expect(facts.contains { $0.fact == .modifier(name: "indirect", isPresent: false) })
            #expect(facts.contains { $0.fact == .enumCaseIndirectStorage(isIndirect: member.name != "empty") && $0.confidence == .corroborated })
        }
        let mixedEnum = try #require(store.declarationsByID.values.first { $0.name == "MixedEnum" && $0.kind == .enumeration })
        let boxed = try #require(store.members(of: mixedEnum.id).first { $0.name == "boxed" && $0.kind == .enumCase })
        #expect(store.resolvedFactsBySubject[.declaration(boxed.id)]?.contains {
            $0.fact == .modifier(name: "indirect", isPresent: true) && $0.confidence == .corroborated
        } == true)
        let count = store.evidence.count
        try store.merge(compiler)
        try store.merge(binary)
        #expect(store.evidence.count == count)
        #expect(try await writer.write(store).text == output.text)
        var reversed = SymbolIndexStore()
        try await reversed.ingest(MangledSymbolSource(exportedSymbols: symbols, context: context))
        try reversed.merge(binary)
        try reversed.merge(compiler)
        #expect(try await writer.write(reversed).text == output.text)

        // Binary-only recovery emits equivalent case syntax, including generic enums.
        var binaryOnly = SymbolIndexStore()
        try await binaryOnly.ingest(MangledSymbolSource(exportedSymbols: symbols, context: context))
        try binaryOnly.merge(binary)
        let binaryText = try await writer.write(binaryOnly).text
        #expect(binaryText.contains("indirect case boxed"))
        #expect(!binaryText.contains("indirect case empty"))

        // A contradictory binary observation withdraws only the affected modifier.
        let source = SymbolEvidenceSource(kind: .loadedImage, location: "contradiction",
            artifactIdentifier: "other-build", lineageIdentifier: "other-build")
        let contradiction = IndexingResult(source: source, context: context, evidence: [.init(source: source,
            subject: .enumCase(owner: mixedEnum.id, name: "boxed"), fact: .enumCaseIndirectStorage(isIndirect: false), location: "boxed")])
        try store.merge(contradiction)
        #expect(store.resolvedFactsBySubject[.declaration(boxed.id)]?.contains {
            $0.fact == .modifier(name: "indirect", isPresent: true)
        } == false)
        #expect(store.diagnostics.contains { $0.kind == .conflictingInformation && $0.declarationID == boxed.id })
        #expect(try await writer.write(store).text.contains("final class FinalClass"))
        let finalClass = try #require(store.declarationsByID.values.first { $0.name == "FinalClass" && $0.kind == .class })
        let compilerSource = SymbolEvidenceSource(kind: .compilerDump, location: "different SDK",
            artifactIdentifier: "different SDK", lineageIdentifier: "different SDK", producer: "test compiler")
        let finalConflict = IndexingResult(source: compilerSource, context: context, evidence: [.init(source: compilerSource,
            subject: .declaration(finalClass.id), fact: .modifier(name: "final", isPresent: false), location: "FinalClass")])
        try store.merge(finalConflict)
        #expect(store.resolvedFactsBySubject[.declaration(finalClass.id)]?.contains {
            if case .modifier("final", _) = $0.fact { return true }; return false
        } == false)
        #expect(store.diagnostics.contains { $0.kind == .conflictingInformation && $0.declarationID == finalClass.id })

        // A subset of a multi-target interface cannot prove a modifier globally.
        let otherTarget = try CompilerTarget(parsing: "arm64-ios")
        var multipleTargets = SymbolIndexStore()
        try await multipleTargets.ingest(MangledSymbolSource(exportedSymbols: symbols,
            context: .init(moduleName: context.moduleName, targets: context.targets.union([otherTarget]))))
        #expect(throws: SymbolIndexStore.IngestionError.incompatibleContext) { try multipleTargets.merge(compiler) }
        #expect(multipleTargets.evidence.isEmpty)
        #expect(multipleTargets.resolvedFactsBySubject.isEmpty)
    }

    @Test func rejectsIncorrectModuleAndTargetCoverage() throws {
        let source = SymbolEvidenceSource(kind: .compilerDump, location: "fixture", artifactIdentifier: "fixture",
            lineageIdentifier: "fixture", producer: "Swift test")
        let context = IndexingContext(moduleName: "Expected", targets: [try CompilerTarget(parsing: "arm64-macos")])
        #expect(throws: DeclarationModifierSource.ReadError.self) {
            try DeclarationModifierSource.parse(Data(#"{"ABIRoot":{"kind":"Root","name":"Other","children":[]}}"#.utf8), source: source, context: context)
        }
        #expect(throws: IndexingSourceError.self) {
            try DeclarationModifierSource.parse(Data(), source: source,
                context: .init(moduleName: "Expected", targets: [try CompilerTarget(parsing: "arm64-macos"), try CompilerTarget(parsing: "x86_64-macos")]))
        }
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
        guard process.terminationStatus == 0 else { throw TestError.toolFailed(text) }
        return text
    }
    private enum TestError: Error { case toolFailed(String) }
}
