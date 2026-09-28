import SwiftIndexing
import Foundation
import SwiftDemangle
import SwiftParser
import SwiftSyntax
import Testing
@_spi(Testing) @testable import SwiftSymbolIndexStore

struct RemainingGenerationTests {
    @Test func retainsInverseConformanceRequirementsInIndex() async throws {
        let fixtures = [
            (symbol: "_$s7Testing14__requiringTryyxxnKRi_zlF", index: 0, protocolName: "Copyable"),
            (symbol: "_$s20InverseIndexFixtures9escapableyyxRi0_zlF", index: 1, protocolName: "Escapable")
        ]
        for fixture in fixtures {
            var store = SymbolIndexStore()
            try store.merge(fixture.symbol)
            let record = try #require(store.symbolRecordsByMangledName[String(fixture.symbol.dropFirst())])
            #expect(record.role != .unsupported)
            #expect(store.diagnostics.isEmpty)
            let declaration = try #require(store.declarationsByID.values.first { $0.mangledSymbols.contains(fixture.symbol) })
            #expect(declaration.evidence == .direct)
            let signature = try #require(declaration.genericSignature)
            let requirement = try #require(signature.children.first { $0.kind == .dependentGenericInverseConformanceRequirement })
            #expect(requirement.children.count == 2)
            #expect(try requirement.children[1].smallIndex() == fixture.index)
            #expect(requirement.description.contains("~Swift.\(fixture.protocolName)"))
            #expect(declaration.signature?.declarationGenericSignature?.declarationKey == signature.declarationKey)
            let output = try await SwiftInterfaceWriter(configuration: .init(moduleName: "Testing", compilerVersion: "test")).write(store)
            #expect(!output.diagnostics.contains { $0.severity == .error }, "\(output.diagnostics)")
            #expect(!Parser.parse(source: output.text).hasError)
            #expect(output.text.contains("where A: ~Swift.\(fixture.protocolName)"), "\(output.text)")
        }

        let unknownRequirement = SwiftSymbol(kind: .dependentGenericInverseConformanceRequirement, children: [
            SwiftSymbol(kind: .type, children: [SwiftSymbol(kind: .dependentGenericParamType, children: [
                SwiftSymbol(kind: .index, contents: .index(0)), SwiftSymbol(kind: .index, contents: .index(0))
            ])]),
            SwiftSymbol(kind: .number, contents: .index(2))
        ])
        #expect(unknownRequirement.inverseConformanceProtocolName == nil)
        #expect(unknownRequirement.description.contains("Swift.<bit 2>"))
        let unknownSignature = SwiftSymbol(kind: .dependentGenericSignature, children: [unknownRequirement])
        #expect(throws: InterfaceTypeRenderer.RenderingError.self) {
            try InterfaceTypeRenderer(genericParametersByDepth: [0: ["A"]]).requirements(unknownSignature)
        }

        let existentialSymbol = "_$s7Testing4TestV10__function5named2in02xcB18CompatibleSelector11displayName6traits14sourceLocation10parameters12testFunctionACSS_ypRi_s_XPXpSg10ObjectiveC0H0VSgSSSgSayAA0B5Trait_pGAA06SourceM0VSaySS05firstJ0_AR06secondJ0ypXp4typetGyyYaYbKctFZ"
        var store = SymbolIndexStore()
        try store.merge(existentialSymbol)
        let record = try #require(store.symbolRecordsByMangledName[String(existentialSymbol.dropFirst())])
        #expect(record.role != .unsupported)
        let declaration = try #require(store.declarationsByID.values.first { $0.name == "__function" })
        #expect(declaration.evidence == .direct)
        let signature = try #require(declaration.signature)
        let inverseRequirements = inverseConformanceRequirements(in: signature)
        #expect(inverseRequirements.count == 1)
        #expect(try inverseRequirements[0].children[1].smallIndex() == 0)
        let output = try await SwiftInterfaceWriter(configuration: .init(moduleName: "Testing", compilerVersion: "test")).write(store)
        #expect(!output.diagnostics.contains { $0.severity == .error }, "\(output.diagnostics)")
        #expect(!Parser.parse(source: output.text).hasError)
        #expect(output.text.contains("any ~Swift.Copyable.Type"), "\(output.text)")
    }

    @Test func rendersRecoveredTypesAndConformances() async throws {
        for fixture in RemainingGenerationFixture.allCases {
            var store = SymbolIndexStore()
            try store.merge(fixture.input)
            let output = try await SwiftInterfaceWriter(configuration: .init(moduleName: "Example", compilerVersion: "test")).write(store)
            #expect(!output.diagnostics.contains { $0.severity == .error }, "\(fixture): \(output.diagnostics)")
            #expect(!Parser.parse(source: output.text).hasError)
            let normalized = output.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            for expected in fixture.expected { #expect(normalized.contains(expected), "\(output.text)") }
        }
    }

    @Test func preservesIndexedGenericSignaturesAndRendersAllMissingScopes() async throws {
        let url = try #require(Bundle.module.url(forResource: "RemainingGenericScopes.symbols", withExtension: "txt", subdirectory: "TestData"))
        let inputs = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
        #expect(inputs.count == 40) // 24 declarations, including their separate accessor exports.
        var store = SymbolIndexStore()
        try await store.merge(contentsOf: inputs)
        for record in store.symbolRecordsByMangledName.values {
            #expect(record.role != .unsupported)
            let original = try SwiftSymbol(try #require(record.mangledSymbols.first))
            #expect(record.demangledSymbol.declarationKey == original.declarationKey)
            for identifier in record.declarationIDs {
                let declaration = try #require(store.declarationsByID[identifier])
                if let signature = declaration.signature {
                    #expect(contains(signature, in: original))
                    #expect(declaration.genericSignature?.declarationKey == signature.declarationGenericSignature?.declarationKey)
                }
            }
        }
        let writer = SwiftInterfaceWriter(configuration: .init(moduleName: "AppIntents", compilerVersion: "test"))
        let output = try await writer.write(store)
        #expect(!output.diagnostics.contains { $0.severity == .error }, "\(output.diagnostics)")
        #expect(output.text.contains("buildBlock<A1, B1>(_: A1, _: B1)"))
        #expect(output.text.contains("enum PhraseBuilder<A>"))
        #expect(output.text.contains("class EntityProjection<A>"))
        #expect(output.text.contains("Swift.KeyPath<A, A1>"))
        var reversed = SymbolIndexStore()
        try await reversed.merge(contentsOf: inputs.reversed())
        #expect(try await writer.write(reversed).text == output.text)
    }

    @Test func retainsBoundTypeAndConditionalRequirementsInConformanceIndex() throws {
        for fixture in [RemainingGenerationFixture.sceneConformance, .optionalConformance] {
            var store = SymbolIndexStore()
            try store.merge(fixture.input)
            let conformance = try #require(store.conformances.first)
            let original = try SwiftSymbol(fixture.input)
            #expect(contains(conformance.conformingType, in: original))
            #expect(contains(conformance.protocolType, in: original))
            #expect(containsGenericParameter(in: conformance.conformingType, depth: 0, index: 0))
            if fixture == .optionalConformance {
                #expect(conformance.genericSignature?.children.filter { $0.kind == .dependentGenericConformanceRequirement }.count == 2)
            }
        }
    }

    @Test func matchesAbsoluteGenericDepthsIncludingEmptyScopes() throws {
        let signature = SwiftSymbol(kind: .dependentGenericSignature, children: [1, 0, 2].map {
            SwiftSymbol(kind: .dependentGenericParamCount, contents: .index(UInt64($0)))
        })
        var renderer = InterfaceTypeRenderer(genericParametersByDepth: [0: ["A"]])
        let clause = try renderer.addGenericParameters(signature, startingAt: 1, avoiding: [])
        #expect(renderer.genericParametersByDepth == [0: ["A"], 1: [], 2: ["A2", "B2"]])
        #expect(clause?.formatted().description == "<A2, B2>")
    }

    @Test func preservesMetadataAndMultiScopeIndexEvidence() async throws {
        var store = SymbolIndexStore()
        let metadata = ["_$s7SwiftUI30_EnvironmentKeyWritingModifierVMa", "_$s7SwiftUI30_EnvironmentKeyWritingModifierVMn"]
        try await store.merge(contentsOf: metadata + [RemainingGenerationFixture.sceneConformance.input,
                                                     RemainingGenerationFixture.nestedEnum.input])
        #expect(store.symbolRecordsByMangledName["$s7SwiftUI30_EnvironmentKeyWritingModifierVMa"]?.role == .metadata)
        #expect(store.symbolRecordsByMangledName["$s7SwiftUI30_EnvironmentKeyWritingModifierVMn"]?.role == .descriptor)
        let modifier = try #require(store.declarationsByID.values.first { $0.name == "_EnvironmentKeyWritingModifier" })
        #expect(modifier.evidence == .direct)
        let enumCase = try #require(store.declarationsByID.values.first { $0.name == "rtree" })
        let signature = try #require(enumCase.genericSignature)
        #expect(try signature.children.filter { $0.kind == .dependentGenericParamCount }.map { try $0.smallIndex() } == [1, 1])
        #expect(containsGenericParameter(in: signature, depth: 0, index: 0))
        #expect(containsGenericParameter(in: signature, depth: 1, index: 0))
        let output = try await SwiftInterfaceWriter(configuration: .init(moduleName: "Example", compilerVersion: "test")).write(store)
        #expect(!output.diagnostics.contains { $0.severity == .error })
    }

    private func contains(_ expected: SwiftSymbol, in node: SwiftSymbol) -> Bool {
        node.declarationKey == expected.declarationKey || node.children.contains { contains(expected, in: $0) }
    }

    private func containsGenericParameter(in node: SwiftSymbol, depth: Int, index: Int) -> Bool {
        if let position = try? node.parameterPosition(), position == (depth, index) { return true }
        return node.children.contains { containsGenericParameter(in: $0, depth: depth, index: index) }
    }

    private func inverseConformanceRequirements(in node: SwiftSymbol) -> [SwiftSymbol] {
        (node.kind == .dependentGenericInverseConformanceRequirement ? [node] : [])
            + node.children.flatMap(inverseConformanceRequirements)
    }
}
