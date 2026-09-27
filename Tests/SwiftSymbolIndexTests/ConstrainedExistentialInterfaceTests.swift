import SwiftDemangle
import SwiftParser
import SwiftSyntax
import Testing
@testable import SwiftSymbolIndexStore

struct ConstrainedExistentialInterfaceTests {
    @Test func rendersSDKConstrainedExistentials() async throws {
        for fixture in ConstrainedExistentialInterfaceFixture.allCases {
            var store = SymbolIndexStore()
            try await store.merge(contentsOf: fixture.contextSymbols)
            try store.merge(fixture.input)
            #expect(store.symbolRecordsByMangledName.values.allSatisfy { $0.role != .unsupported })
            let output = try await SwiftInterfaceWriter(configuration: .init(moduleName: "SwiftUI", compilerVersion: "test")).write(store)
            #expect(!output.diagnostics.contains { $0.severity == .error }, "\(fixture): \(output.diagnostics)")
            #expect(!Parser.parse(source: output.text).hasError)
            let normalized = output.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            #expect(normalized.contains(fixture.expected), "\(fixture): \(output.text)")
            #expect(output.diagnostics.contains { $0.message.contains("Primary associated type syntax follows encoded constraint order") })
        }
    }

    @Test func recoversPrimaryAssociatedTypeDeclarationsFromCompilerSymbols() async throws {
        let symbols = [
            "_$s19ExistentialFixtures16concreteMetatypeyyAA3Box_pSi5ValueAaCPRts_XPXpF",
            "_$s19ExistentialFixtures17containerMetatypeyyAA3Box_pSi5ValueAaCPRts_XPmF",
            "_$s19ExistentialFixtures3BoxMp",
            "_$s5Value19ExistentialFixtures3BoxPTl"
        ]
        let writer = SwiftInterfaceWriter(configuration: .init(moduleName: "ExistentialFixtures", compilerVersion: "test"))
        var store = SymbolIndexStore()
        try await store.merge(contentsOf: symbols)
        let output = try await writer.write(store)
        #expect(!output.diagnostics.contains { $0.severity == .error })
        #expect(output.text.contains("public protocol Box<Value>"))
        #expect(output.text.contains("any ExistentialFixtures.Box<Swift.Int>.Type"))
        #expect(output.text.contains("(any ExistentialFixtures.Box<Swift.Int>).Type"))
        var reversed = SymbolIndexStore()
        try await reversed.merge(contentsOf: symbols.reversed())
        #expect(try await writer.write(reversed).text == output.text)
    }

    @Test func distinguishesExistentialMetatypes() throws {
        let root = try SwiftSymbol(ConstrainedExistentialInterfaceFixture.sequence.input)
        let existential = try #require(findExistential(in: root))
        let renderer = InterfaceTypeRenderer(genericParametersByDepth: [0: ["Int"]])
        let instance = SwiftSymbol(kind: .type, children: [existential])
        let concreteMetatype = try renderer.type(SwiftSymbol(kind: .existentialMetatype, children: [instance])).formatted().description
        let containerMetatype = try renderer.type(SwiftSymbol(kind: .metatype, children: [instance])).formatted().description
        #expect(concreteMetatype == "any Swift.Sequence<Int>.Type")
        #expect(containerMetatype == "(any Swift.Sequence<Int>).Type")
    }

    @Test func preservesConstraintOrderForAllProtocols() throws {
        let root = try SwiftSymbol(ConstrainedExistentialInterfaceFixture.asyncIterator.input)
        let existential = try #require(findExistential(in: root))
        let reversed = SwiftSymbol(kind: .constrainedExistential, children: [existential.children[0],
            SwiftSymbol(kind: .constrainedExistentialRequirementList, children: existential.children[1].children.reversed())])
        let renderer = InterfaceTypeRenderer(genericParametersByDepth: [0: ["Int", "Never"]])
        #expect(try renderer.type(reversed).formatted().description == "any Swift.AsyncIteratorProtocol<Never, Int>")
        let unknownProtocol = SwiftSymbol(kind: .protocol, children: [
            SwiftSymbol(kind: .module, contents: .name("Example")),
            SwiftSymbol(kind: .identifier, contents: .name("Pair"))])
        let unknown = SwiftSymbol(kind: .constrainedExistential, children: [
            SwiftSymbol(kind: .type, children: [SwiftSymbol(kind: .protocolList, children: [
                SwiftSymbol(kind: .typeList, children: [SwiftSymbol(kind: .type, children: [unknownProtocol])])])]),
            reversed.children[1]])
        #expect(try renderer.type(unknown).formatted().description == "any Example.Pair<Never, Int>")
    }

    private func findExistential(in node: SwiftSymbol) -> SwiftSymbol? {
        if node.kind == .constrainedExistential { return node }
        return node.children.lazy.compactMap { findExistential(in: $0) }.first
    }
}
