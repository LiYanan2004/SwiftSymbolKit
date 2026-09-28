import SwiftIndexing
import Foundation
import SwiftParser
import Testing
@_spi(Testing) @testable import SwiftSymbolIndexStore

struct ParameterPackTests {
    @Test func reconstructsCompilerEmittedPacks() async throws {
        for fixture in ParameterPackFixture.allCases {
            var store = SymbolIndexStore()
            try await store.merge(contentsOf: fixture.input)
            let writer = SwiftInterfaceWriter(configuration: .init(moduleName: "PackFixtures", compilerVersion: "test", imports: ["Swift"]))
            let output = try await writer.write(store)
            #expect(!output.diagnostics.contains { $0.severity == .error })
            #expect(!Parser.parse(source: output.text).hasError)
            let normalized = output.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            for fragment in fixture.expectedFragments {
                #expect(normalized.contains(fragment), "Missing: \(fragment)\n\(output.text)")
            }
            var reversed = SymbolIndexStore()
            try await reversed.merge(contentsOf: fixture.input.reversed())
            #expect(try await writer.write(reversed).text == output.text)
        }
    }
}

private enum ParameterPackFixture: CaseIterable {
    case complete, propertyOnly

    var input: [String] {
        get throws {
            if self == .propertyOnly { return ["_$s12PackFixtures0A3BoxV6valuesxxQp_tvg"] }
            let url = Bundle.module.url(forResource: "ParameterPacks.symbols", withExtension: "txt", subdirectory: "TestData")!
            return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
        }
    }

    var expectedFragments: [String] {
        let shared = ["public struct PackBox<each A>", "public var values: (repeat each A)"]
        if self == .propertyOnly { return shared }
        return shared + [
            "public struct Mixed<A, each B>",
            "public init(_: repeat each A)",
            "PackFixtures.PackBox< >",
            "PackFixtures.PackBox<Swift.Int, Swift.String>",
            "PackFixtures.PackBox<repeat each A>",
            "PackFixtures.Mixed<Swift.Int, Swift.String, repeat each A>",
            "extension PackFixtures.PackBox: PackFixtures.Marker where repeat each A: Swift.Equatable"
        ]
    }
}
