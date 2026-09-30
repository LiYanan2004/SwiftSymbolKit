import Testing
import MachOKit
@testable import SwiftIndexing

struct LoadedImageSourceTests {
    @Test func resolvesAllCachedOpaqueSymbolsRepeatedly() throws {
        let cache = try #require(DyldCacheLoaded.current)
        let images = Array(cache.machOImages())
        let image = try #require(images.first { $0.path?.hasSuffix("/SwiftUI") == true })
        let symbols = image.exportedSymbols.filter {
            $0.name.hasSuffix("QOMQ") && $0.flags.kind == .regular &&
            !$0.flags.contains(.reexport) && $0.resolverOffset == nil
        }
        #expect(!symbols.isEmpty)
        let resolver = MachOImageSymbolResolver(images: images)
        for symbol in symbols {
            let offset = try #require(symbol.offset)
            let expected = UInt64(UInt(bitPattern: image.ptr)) + UInt64(offset)
            let normalized = MangledSymbolSource.normalizedSymbol(symbol.name)
            #expect(try resolver.address(of: symbol.name, in: image) == expected)
            #expect(try resolver.address(of: normalized, in: image) == expected)
        }
        for _ in 0..<2 {
            #expect(throws: LoadedImageSource.ReadError.self) {
                try resolver.address(of: "$sMissingOpaqueDescriptorQOMQ", in: image)
            }
        }
    }

    @Test func readsCurrentSharedCache() async throws {
        let cache = try #require(DyldCacheLoaded.current)
        let image = try #require(cache.machOImages().first { $0.path?.hasSuffix("/SwiftUI") == true })
        let target = try LoadedImageSource.identity(of: image).target
        let symbols = Array(image.exportedSymbols.map(\.name).filter { $0.hasSuffix("QOMQ") }.sorted().prefix(10))
        #expect(!symbols.isEmpty)
        let result = try await LoadedImageSource(imageInstallName: image.path,
            descriptorSymbols: symbols, context: .init(moduleName: "SwiftUI", targets: [target])).read()
        #expect(!result.evidence.isEmpty, "\(result.diagnostics.map(\.message))")
        #expect(result.source.location == image.path)
        #expect(result.context.targets == [target])
    }

    @Test func reportsMissingCacheImage() async throws {
        let context = IndexingContext(moduleName: "Missing", targets: [try CompilerTarget(parsing: "arm64-macos")])
        do {
            _ = try await LoadedImageSource(imageInstallName: "/missing/library.dylib",
                descriptorSymbols: [], context: context).read()
            Issue.record("Expected a missing cache image error")
        } catch LoadedImageSource.ReadError.imageNotInSharedCache(let name) {
            #expect(name == "/missing/library.dylib")
        }
    }

    @Test func reportsPlatformMismatchForIPhoneOSTarget() throws {
        let error = LoadedImageSource.ReadError.platformOrArchMismatch(
            expect: [try CompilerTarget(parsing: "arm64-ios")],
            real: try CompilerTarget(parsing: "arm64-macos"))
        #expect(error.description == "Loaded MachO Image mismatch: expected [arm64-ios], but get arm64-macos")
    }

    @Test func reportsArchitectureMismatch() throws {
        let error = LoadedImageSource.ReadError.platformOrArchMismatch(
            expect: [try CompilerTarget(parsing: "arm64e.x1-macos")],
            real: try CompilerTarget(parsing: "arm64-macos"))
        #expect(error.description == "Loaded MachO Image mismatch: expected [arm64e.x1-macos], but get arm64-macos")
    }

    @Test(arguments: ["simulator", "macabi"])
    func reportsEnvironmentMismatch(environment: String) throws {
        let error = LoadedImageSource.ReadError.platformOrArchMismatch(
            expect: [try CompilerTarget(parsing: "arm64-ios-\(environment)")],
            real: try CompilerTarget(parsing: "arm64-ios"))
        #expect(error.description == "Loaded MachO Image mismatch: expected [arm64-ios-\(environment)], but get arm64-ios")
    }

    @Test func reportsEveryExpectedTargetInStableOrder() throws {
        let error = LoadedImageSource.ReadError.platformOrArchMismatch(
            expect: [try CompilerTarget(parsing: "arm64e-ios"), try CompilerTarget(parsing: "arm64-ios")],
            real: try CompilerTarget(parsing: "arm64e-macos"))
        #expect(error.description == "Loaded MachO Image mismatch: expected [arm64-ios, arm64e-ios], but get arm64e-macos")
    }

    @Test func preservesTargetCombinations() throws {
        let error = LoadedImageSource.ReadError.platformOrArchMismatch(
            expect: [try CompilerTarget(parsing: "arm64-ios"), try CompilerTarget(parsing: "x86_64-macos")],
            real: try CompilerTarget(parsing: "arm64-macos"))
        #expect(error.description == "Loaded MachO Image mismatch: expected [arm64-ios, x86_64-macos], but get arm64-macos")
    }
}
