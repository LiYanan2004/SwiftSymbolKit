import SwiftDemangle
import SwiftParser
import Testing
@testable import SwiftSymbolIndexStore

struct ExtensionTypeTests {
    @Test func rendersSDKMembersReturningExtensionNestedTypes() async throws {
        for fixture in ExtensionTypeFixture.allCases {
            var store = SymbolIndexStore()
            try await store.merge(contentsOf: fixture.input)
            let writer = SwiftInterfaceWriter(configuration: .init(moduleName: "SwiftUI", compilerVersion: "test"))
            let output = try await writer.write(store)
            #expect(!output.diagnostics.contains { $0.severity == .error })
            #expect(!Parser.parse(source: output.text).hasError)
            let normalized = output.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            #expect(normalized.contains(fixture.expected), "\(output.text)")
            var reverse = SymbolIndexStore()
            try await reverse.merge(contentsOf: fixture.input.reversed())
            #expect(try await writer.write(reverse).text == output.text)
        }
    }

    @Test func qualifiesThroughExtendedTypeRatherThanExtensionModule() throws {
        let nominal = SwiftSymbol(kind: .structure, children: [
            SwiftSymbol(kind: .module, contents: .name("Original")),
            SwiftSymbol(kind: .identifier, contents: .name("Container"))
        ])
        for constrained in [false, true] {
            let context = SwiftSymbol(kind: .extension, children: [
                SwiftSymbol(kind: .module, contents: .name("Extensions")), nominal
            ] + (constrained ? [SwiftSymbol(kind: .dependentGenericSignature)] : []))
            let nested = SwiftSymbol(kind: .structure, children: [context,
                SwiftSymbol(kind: .identifier, contents: .name("Nested"))])
            #expect(try InterfaceTypeRenderer().type(nested).description == "Original.Container.Nested")
        }
    }

    @Test func rejectsMalformedExtensionContexts() {
        for children in [[], [SwiftSymbol(kind: .module)],
                         [SwiftSymbol(kind: .identifier), SwiftSymbol(kind: .structure)],
                         [SwiftSymbol(kind: .module), SwiftSymbol(kind: .structure), SwiftSymbol(kind: .identifier)]] {
            #expect(throws: InterfaceTypeRenderer.RenderingError.self) {
                try InterfaceTypeRenderer().type(SwiftSymbol(kind: .extension, children: children))
            }
        }
    }
}

private enum ExtensionTypeFixture: CaseIterable {
    case tag, resolveHDR, hostingRenderer
    var input: [String] {
        switch self {
        case .tag: return [
            "_$sSo10CGColorRefa7SwiftUIE3tagAC5ColorVACE11ProviderTagOvg",
            "_$sSo10CGColorRefa7SwiftUIE3tagAC5ColorVACE11ProviderTagOvpMV"
        ]
        case .resolveHDR: return ["_$sSo10CGColorRefa7SwiftUIE10resolveHDR2inAC5ColorVACE08ResolvedF0VAC17EnvironmentValuesV_tF"]
        case .hostingRenderer: return ["_$s7SwiftUI13NSHostingViewC8rendererAA11DisplayListVAAE0D8RendererCvg"]
        }
    }
    var expected: String {
        switch self {
        case .tag: return "public var tag: SwiftUI.Color.ProviderTag { get }"
        case .resolveHDR: return "public func resolveHDR(`in`: SwiftUI.EnvironmentValues) -> SwiftUI.Color.ResolvedHDR"
        case .hostingRenderer: return "public var renderer: SwiftUI.DisplayList.ViewRenderer { get }"
        }
    }
}
