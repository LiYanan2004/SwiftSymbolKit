import Foundation
import SwiftDemangle
import SwiftIndexing
import SwiftSymbolIndexStore
import Testing

struct ClangTypeNameTests {
    private let imageIdentity = ClangTypeIdentity(kind: .typeAlias, name: "CGImageRef")
    private let imageSymbol = "$s14ClangNameProbe7resolveyySo10CGImageRefaF"
    private let context = IndexingContext(moduleName: "Example", targets: [.init(architecture: .arm64, platform: .macOS)])
    
    @Test func verifiesCompleteParameterIdentity() throws {
        #expect(ClangTypeIdentity.probeIdentity(mangledSymbol: imageSymbol) == imageIdentity)
        #expect(ClangTypeIdentity.probeIdentity(mangledSymbol: "$s14ClangNameProbe7resolveyySo10CGImageRefaSgF") == nil)
        #expect(ClangTypeIdentity.probeIdentity(mangledSymbol: "$s14ClangNameProbe7resolveyySo8NSObjectCF") == .init(kind: .class, name: "NSObject"))
        #expect(ClangTypeIdentity.probeIdentity(mangledSymbol: "$s14ClangNameProbe7resolveyySo8NSObject_pF") == .init(kind: .protocol, name: "NSObject"))
        #expect(ClangTypeIdentity.probeIdentity(mangledSymbol: "$s14ClangNameProbe7resolveyySo8NSObjectC_SitF") == nil)
        #expect(ClangTypeIdentity.probeIdentity(mangledSymbol: "$s14ClangNameProbe7resolveyySiF") == nil)
        #expect(ClangTypeIdentity.probeIdentity(mangledSymbol: "invalid") == nil)
        let tree = try DemangledNode(imageSymbol)
        #expect(ClangTypeIdentity.occurrences(in: tree) == [imageIdentity])
    }
    
    @Test func prefersNominalNamesAndPreservesAliases() {
        let nominal = candidate("CGImage", kind: "swift.class")
        let alias = candidate("ImageAlias", kind: "swift.typealias")
        let resolution = ClangTypeNameResolution(identity: imageIdentity, candidates: [alias, nominal, nominal])
        #expect(resolution.candidates.count == 2)
        #expect(resolution.swiftName == nominal.swiftName)
        #expect(resolution.status == .resolved)
        #expect(ClangTypeNameResolution(identity: imageIdentity, candidates: []).status == .unresolved)
        #expect(ClangTypeNameResolution(identity: imageIdentity,
                                        candidates: [alias, candidate("SecondAlias", kind: "swift.typealias")]).status == .ambiguous)
    }
    
    @Test func indexesBothDirectionsAndRetainsAmbiguityAcrossMerges() async throws {
        var index = SymbolIndexStore()
        let result = observation([candidate("CGImage", kind: "swift.class")])
        #expect(throws: SymbolIndexStore.IngestionError.primarySourceRequired) { try index.merge(result) }
        try await index.ingest(MangledSymbolSource(exportedSymbols: ["$s7Example3FooVMn"], context: context))
        let originalDeclarations = Set(index.declarationsByID.keys)
        try index.merge(result)
        try index.merge(result)
        #expect(index.evidence.count == 1)
        #expect(index.clangTypeNamesByClangIdentity[imageIdentity]?.swiftName?.qualifiedName == "CoreGraphics.CGImage")
        let alias = candidate("ImageAlias", kind: "swift.typealias")
        try index.merge(observation([alias]))
        #expect(index.clangTypeIdentitiesBySwiftName[alias.swiftName] == [imageIdentity])
        #expect(index.clangTypeNamesByClangIdentity[imageIdentity]?.status == .resolved)
        try index.merge(observation([candidate("OtherImage", kind: "swift.class")]))
        #expect(index.clangTypeNamesByClangIdentity[imageIdentity]?.status == .ambiguous)
        #expect(index.clangTypeNamesByClangIdentity[imageIdentity]?.swiftName == nil)
        #expect(index.diagnostics.contains { $0.kind == .conflictingInformation })
        #expect(Set(index.declarationsByID.keys) == originalDeclarations)
        try index.merge(observation([]))
        #expect(index.clangTypeNamesByClangIdentity[imageIdentity]?.candidates.count == 3)
    }
    
    @Test func rejectsIncompatibleOrInvalidObservationsWithoutMutation() async throws {
        var index = SymbolIndexStore()
        try await index.ingest(MangledSymbolSource(exportedSymbols: ["$s7Example3FooVMn"], context: context))
        try index.merge(observation([candidate("CGImage", kind: "swift.class")]))
        let original = index.clangTypeNamesByClangIdentity
        #expect(throws: SymbolIndexStore.IngestionError.incompatibleContext) {
            try index.merge(observation([], producer: "another-compiler"))
        }
        let invalid = ClangTypeName(identity: imageIdentity, swiftName: .init(moduleName: "Swift", pathComponents: ["Int"]),
                                    requiredImport: "Swift", clangUSR: "c:@T@CGImageRef", declarationKind: "swift.struct",
                                    probeSymbol: "$s14ClangNameProbe7resolveyySiF")
        #expect(throws: SymbolIndexStore.IngestionError.unsupportedSupplementalFact) {
            try index.merge(observation([invalid]))
        }
        #expect(index.clangTypeNamesByClangIdentity == original)
        var multipleTargets = SymbolIndexStore()
        let combined = IndexingContext(moduleName: "Example", targets: context.targets.union([.init(architecture: .x86_64, platform: .macOS)]))
        try await multipleTargets.ingest(MangledSymbolSource(exportedSymbols: ["$s7Example3FooVMn"], context: combined))
        #expect(throws: SymbolIndexStore.IngestionError.incompatibleContext) { try multipleTargets.merge(observation([])) }
        #expect(multipleTargets.clangTypeNamesByClangIdentity.isEmpty)
    }
    
    @Test func resolvesSDKTypesFromExplicitImportedModules() async throws {
        let compilerPath = try xcrun(["--find", "swiftc"])
        let sdkPath = try xcrun(["--sdk", "macosx", "--show-sdk-path"])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ClangTypeNames-\(UUID().uuidString)")
        let resolver = ClangTypeNameResolver(configuration: .init(
            toolchainDirectory: URL(fileURLWithPath: compilerPath).deletingLastPathComponent().path,
            sdkPath: sdkPath, targetTriple: "arm64-apple-macosx15.0"))
        let expected: [(ClangTypeIdentity.Kind, String, String)] = [
            (.typeAlias, "CGImageRef", "CoreGraphics.CGImage"),
            (.structure, "CGError", "CoreGraphics.CGError"),
            (.structure, "CGPoint", "CoreFoundation.CGPoint"),
            (.structure, "NSComparisonResult", "Foundation.ComparisonResult"),
            (.typeAlias, "NSNotificationName", "Foundation.NSNotification.Name"),
            (.structure, "_NSRange", "Foundation.NSRange"),
            (.protocol, "NSCopying", "Foundation.NSCopying"),
            (.class, "NSObject", "ObjectiveC.NSObject"),
            (.protocol, "NSObject", "ObjectiveC.NSObjectProtocol"),
            (.class, "NSString", "Foundation.NSString"),
        ]
        let negatives: Set<ClangTypeIdentity> = [.init(kind: .structure, name: "CGImageRef"),
                                                 .init(kind: .structure, name: "NSNotificationName"), .init(kind: .structure, name: "MissingClangType")]
        let requests = Set(expected.map { ClangTypeIdentity(kind: $0.0, name: $0.1) }).union(negatives)
        let result = try resolver.resolve(requests, importedModules: ["CoreGraphics", "CoreFoundation", "Foundation", "ObjectiveC"],
                                          context: context, outputDirectory: directory)
        var index = SymbolIndexStore()
        try await index.ingest(MangledSymbolSource(exportedSymbols: ["$s7Example3FooVMn"], context: context))
        try index.merge(result)
        #expect(index.clangTypeNamesByClangIdentity.count == requests.count)
        for (kind, name, swiftName) in expected {
            let identity = ClangTypeIdentity(kind: kind, name: name)
            let resolution = try #require(index.clangTypeNamesByClangIdentity[identity])
            #expect(resolution.status == .resolved, "\(name): \(resolution.candidates)")
            #expect(resolution.swiftName?.qualifiedName == swiftName)
            let resolved = try #require(resolution.swiftName)
            #expect(index.clangTypeIdentitiesBySwiftName[resolved] == [identity])
            #expect(resolution.candidates.allSatisfy { !$0.probeSymbol.isEmpty && !$0.clangUSR.isEmpty })
        }
        for identity in negatives {
            #expect(index.clangTypeNamesByClangIdentity[identity]?.status == .unresolved)
        }
        #expect(index.clangTypeNamesByClangIdentity[.init(kind: .structure, name: "CGPoint")]?.candidates
            .contains { $0.swiftName.qualifiedName == "Foundation.NSPoint" } == true)
        try FileManager.default.removeItem(at: directory)
    }
    
    @Test func resolvesClangTypesFromRealSwiftUIExport() async throws {
        // Captured from macOS 26.2 SDK, SwiftUI.framework/Versions/A/SwiftUI.tbd.
        // Exported for x86_64-macos, arm64-macos and arm64e-macos:
        // SwiftUI._ArchivedViewHost.filteredImage(__C.CGImageRef) throws -> __C.CGImageRef
        let symbol = "_$s7SwiftUI17_ArchivedViewHostC13filteredImageySo10CGImageRefaAFKF"
        let context = IndexingContext(moduleName: "SwiftUI", targets: [.init(architecture: .arm64, platform: .macOS)])
        var index = SymbolIndexStore()
        try await index.ingest(MangledSymbolSource(exportedSymbols: [symbol], context: context))
        let normalizedSymbol = MangledSymbolSource.normalizedSymbol(symbol)
        let record = try #require(index.symbolRecordsByMangledName[normalizedSymbol])
        let declaration = try #require(record.declarationIDs.compactMap { index.declarationsByID[$0] }
            .first { $0.name == "filteredImage" })
        let signature = try #require(declaration.signature)
        let requests = ClangTypeIdentity.occurrences(in: record.demangledSymbol)
        #expect(requests == [imageIdentity])
        #expect(ClangTypeIdentity.occurrences(in: signature) == requests)

        let compilerPath = try xcrun(["--find", "swiftc"])
        let sdkPath = try xcrun(["--sdk", "macosx", "--show-sdk-path"])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ClangTypeNames-SwiftUI-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let resolver = ClangTypeNameResolver(configuration: .init(
            toolchainDirectory: URL(fileURLWithPath: compilerPath).deletingLastPathComponent().path,
            sdkPath: sdkPath, targetTriple: "arm64-apple-macosx15.0"))
        let result = try resolver.resolve(requests, importedModules: ["CoreGraphics"],
                                          context: context, outputDirectory: directory)
        try index.merge(result)

        let resolution = try #require(index.clangTypeNamesByClangIdentity[imageIdentity])
        let swiftName = SwiftTypeName(moduleName: "CoreGraphics", pathComponents: ["CGImage"])
        #expect(resolution.status == .resolved)
        #expect(resolution.swiftName == swiftName)
        #expect(index.clangTypeIdentitiesBySwiftName[swiftName] == [imageIdentity])
        #expect(resolution.candidates.contains {
            $0.swiftName == swiftName && $0.requiredImport == "CoreGraphics"
                && ClangTypeIdentity.probeIdentity(mangledSymbol: $0.probeSymbol) == imageIdentity
        })
        let preservedSignature = try #require(index.declarationsByID[declaration.id]?.signature)
        #expect(ClangTypeIdentity.occurrences(in: preservedSignature) == requests)
        #expect(index.exportedSymbols == [normalizedSymbol])
    }

    @Test func resolvesUsingTheSelectedIOSSDKAndTarget() async throws {
        let compilerPath = try xcrun(["--find", "swiftc"])
        let sdkPath = try xcrun(["--sdk", "iphoneos", "--show-sdk-path"])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ClangTypeNames-iOS-\(UUID().uuidString)")
        let resolver = ClangTypeNameResolver(configuration: .init(
            toolchainDirectory: URL(fileURLWithPath: compilerPath).deletingLastPathComponent().path,
            sdkPath: sdkPath, targetTriple: "arm64-apple-ios18.0"))
        let context = IndexingContext(moduleName: "Example", targets: [.init(architecture: .arm64, platform: .iOS)])
        let errorIdentity = ClangTypeIdentity(kind: .structure, name: "CGError")
        let result = try resolver.resolve([imageIdentity, errorIdentity], importedModules: ["CoreGraphics"],
                                          context: context, outputDirectory: directory)
        var index = SymbolIndexStore()
        try await index.ingest(MangledSymbolSource(exportedSymbols: ["$s7Example3FooVMn"], context: context))
        try index.merge(result)
        #expect(index.clangTypeNamesByClangIdentity[imageIdentity]?.swiftName?.qualifiedName == "CoreGraphics.CGImage")
        #expect(index.clangTypeNamesByClangIdentity[errorIdentity]?.swiftName?.qualifiedName == "CoreGraphics.CGError")
        #expect(throws: ClangTypeNameResolver.ResolutionError.incompatibleContext) {
            try resolver.resolve([imageIdentity], importedModules: ["CoreGraphics"], context: self.context,
                                 outputDirectory: directory.appendingPathComponent("incompatible"))
        }
        try FileManager.default.removeItem(at: directory)
    }
    
    private func candidate(_ name: String, kind: String) -> ClangTypeName {
        .init(identity: imageIdentity, swiftName: .init(moduleName: "CoreGraphics", pathComponents: [name]),
              requiredImport: "CoreGraphics", clangUSR: "c:@T@CGImageRef", declarationKind: kind, probeSymbol: imageSymbol)
    }
    
    private func observation(_ candidates: [ClangTypeName], producer: String = "test-compiler") -> IndexingResult {
        let source = SymbolEvidenceSource(kind: .compilerDump, location: "test", artifactIdentifier: "test",
                                          lineageIdentifier: "test", producer: producer)
        return .init(source: source, context: context, evidence: [.init(source: source, subject: .module(context.moduleName),
                                                                        fact: .clangTypeName(.init(identity: imageIdentity, candidates: candidates)), location: "test")])
    }
    
    private func xcrun(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ClangTypeNameResolver.ResolutionError.unsupportedName("xcrun \(arguments)") }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
