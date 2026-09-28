import SwiftIndexing
import Foundation
import SwiftDemangle
import SwiftParser
import Testing
@_spi(Testing) @testable import SwiftSymbolIndexStore

struct InterfaceRecoveryTests {
    @Test func recoversNamesAndExtensionGenericScopes() async throws {
        for fixture in InterfaceRecoveryFixture.allCases {
            var store = SymbolIndexStore()
            try await store.merge(contentsOf: fixture.input)
            let writer = SwiftInterfaceWriter(configuration: .init(moduleName: "SwiftUI", compilerVersion: "test"))
            let output = try await writer.write(store)
            #expect(!output.diagnostics.contains { $0.severity == .error }, "\(fixture): \(output.diagnostics)")
            #expect(!Parser.parse(source: output.text).hasError)
            let normalized = output.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            for expected in fixture.expected {
                #expect(normalized.contains(expected), "\(fixture): \(output.text)")
            }
            var reverse = SymbolIndexStore()
            try await reverse.merge(contentsOf: fixture.input.reversed())
            #expect(try await writer.write(reverse).text == output.text)
        }
    }

    @Test func preservesPrivateDiscriminatorsInIndex() async throws {
        let inputs = ["$s7Example5hello6_firstLLyyF", "$s7Example5hello7_secondLLyyF"]
        var store = SymbolIndexStore()
        try await store.merge(contentsOf: inputs)
        #expect(store.declarationsByID.count == 2)
        #expect(store.declarationsByID.values.allSatisfy { $0.name == "hello" && $0.nameNode?.kind == .privateDeclName })
        let output = try await SwiftInterfaceWriter(configuration: .init(moduleName: "Example", compilerVersion: "test")).write(store)
        #expect(output.diagnostics.filter { $0.message.contains("Private or local declaration") }.count == 2)
        #expect(!output.diagnostics.contains { $0.severity == .error })
        #expect(output.text.components(separatedBy: "public func hello()").count == 3)
    }

    @Test func preservesRecoveredDeclarationContextsAndGenericPositions() async throws {
        var store = SymbolIndexStore()
        for fixture in InterfaceRecoveryFixture.allCases {
            try await store.merge(contentsOf: fixture.input)
        }
        let constants = try #require(store.declarationsByID.values.first { $0.name == "constants" })
        #expect(constants.kind == .property)
        #expect(constants.evidence == .direct)
        #expect(constants.nameNode?.kind == .privateDeclName)
        #expect(constants.accessors == [.modify])
        guard case .declaration(let hostID) = constants.context else {
            Issue.record("Missing GraphHost context"); return
        }
        #expect(store.declarationsByID[hostID]?.name == "GraphHost")

        let closedRangeInitializer = try #require(store.declarationsByID.values.first {
            $0.kind == .initializer && $0.mangledSymbols.contains(InterfaceRecoveryFixture.foreignGeneric.input[0])
        })
        guard case .typeExtension(let rangeExtension) = closedRangeInitializer.context else {
            Issue.record("Missing ClosedRange extension context"); return
        }
        #expect(rangeExtension.moduleName == "SwiftUI")
        #expect(store.declarationsByID[rangeExtension.extendedType]?.name == "ClosedRange")
        #expect(genericPositions(in: try #require(closedRangeInitializer.signature)) == ["0:0"])

        let container = try #require(store.declarationsByID.values.first { $0.name == "Container" })
        guard case .typeExtension(let containerExtension) = container.context else {
            Issue.record("Missing Container extension context"); return
        }
        #expect(store.declarationsByID[containerExtension.extendedType]?.name == "_ConditionalContent")
        let initializer = try #require(store.members(of: container.id).first { $0.kind == .initializer })
        guard case .declaration(let parentID) = initializer.context else {
            Issue.record("Missing Container initializer context"); return
        }
        #expect(parentID == container.id)
        #expect(genericPositions(in: try #require(initializer.signature)) == ["0:0", "0:1", "1:0"])
    }

    private func genericPositions(in node: SwiftSymbol) -> Set<String> {
        var positions = Set(node.children.flatMap { genericPositions(in: $0) })
        if node.kind == .dependentGenericParamType, let (depth, index) = try? node.parameterPosition() {
            positions.insert("\(depth):\(index)")
        }
        return positions
    }
}

private enum InterfaceRecoveryFixture: CaseIterable {
    case privateProperty, foreignGeneric, nestedInitializer, nestedConformance
    var input: [String] {
        switch self {
        case .privateProperty: return ["_$s7SwiftUI9GraphHostC9constants33_F9F204BD2F8DB167A76F17F3FB1B3335LLSDyAA11ConstantKeyAELLVSo11AGAttributeaGvM"]
        case .foreignGeneric: return ["_$sSN7SwiftUIE6bounds_SNyxGx_xtcfC"]
        case .nestedInitializer: return ["_$s7SwiftUI19_ConditionalContentVAAE9ContainerV7content8providerAEyxq__qd__G14AttributeGraph0H0VyACyxq_GG_qd__tcfC"]
        case .nestedConformance: return ["_$ss8RangeSetV7SwiftUISxRzSZ6StrideRpzrlE13IndexSequenceVyx_GSTACMc"]
        }
    }
    var expected: [String] {
        switch self {
        case .privateProperty: return ["public var constants: Swift.Dictionary<SwiftUI.ConstantKey, __C.AGAttribute> { get set }"]
        case .foreignGeneric: return ["extension Swift.ClosedRange", "public init(bounds: A, _: A)"]
        case .nestedInitializer: return ["public struct Container<A1>", "public init(content: AttributeGraph.Attribute<SwiftUI._ConditionalContent<A, B>>, provider: A1)"]
        case .nestedConformance: return ["extension Swift.RangeSet.IndexSequence: Swift.Sequence"]
        }
    }
}
