import Foundation
import SwiftDemangle
import Testing
@testable import SwiftSymbolIndexStore

struct ProtocolRequirementTests {
    @Test func extractsProtocolInheritanceAndAssociatedTypePaths() throws {
        for fixture in ProtocolRequirementFixture.allCases {
            let extraction = try SymbolExtractor().extract(fixture.input)
            #expect(extraction.diagnostics.isEmpty)
            #expect(extraction.conformances.isEmpty)
            #expect(extraction.record.role == .descriptor)
            let requirement = try #require(extraction.protocolRequirements.first)
            #expect(extraction.protocolRequirements.count == 1)
            #expect(requirement.associatedTypePath.map { $0.children[0].description } == fixture.expectedPath)
            #expect(requirement.associatedTypePath.map { $0.children[1].description } == fixture.expectedQualifiers)
            #expect(requirement.requiredProtocol.description == fixture.expectedProtocol)
            #expect(requirement.mangledSymbols == [fixture.input])
            let owner = try #require(extraction.declarations.first { $0.id == requirement.protocolID })
            #expect(owner.name == fixture.expectedOwner)
            #expect(owner.kind == .protocol)
            #expect(owner.evidence == .contextOnly)
            #expect(extraction.declarations.filter { $0.kind == .associatedType }.map(\.name) == fixture.expectedMembers)
            #expect(extraction.record.declarationIDs == Set(extraction.declarations.map(\.id)))
        }
    }

    @Test func promotesAssociatedTypesWithoutDuplicatingMembers() throws {
        let requirement = ProtocolRequirementFixture.composition.input
        let descriptor = "_$s5Model11Constraints11CompositionPTl"
        for inputs in [[requirement, descriptor], [descriptor, requirement]] {
            var store = SymbolIndexStore()
            for input in inputs { try store.merge(input) }
            let owner = try #require(store.declarationsByID.values.first { $0.name == "Composition" })
            let members = store.members(of: owner.id)
            #expect(members.count == 1)
            let model = try #require(members.first)
            #expect(model.name == "Model")
            #expect(model.evidence == .direct)
            #expect(model.mangledSymbols == Set(inputs))
            #expect(store.protocolRequirements.count == 1)
            #expect(store.diagnostics.isEmpty)
        }
    }

    @Test func mergesCompositionAndNestedRequirementsInEitherOrder() throws {
        let url = try #require(Bundle.module.url(forResource: "ProtocolConstraints.symbols", withExtension: "txt", subdirectory: "TestData"))
        let inputs = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
        var forward = SymbolIndexStore()
        var reverse = SymbolIndexStore()
        for input in inputs { try forward.merge(input) }
        for input in inputs.reversed() { try reverse.merge(input) }
        #expect(forward.diagnostics.isEmpty)
        #expect(forward.protocolRequirements.count == 12)
        #expect(requirementSnapshot(forward) == requirementSnapshot(reverse))
        let expected: [String: Set<String>] = [
            "Composition": ["Model:Constraints.Foo", "Model:Constraints.Boo"],
            "Dependent": ["Foo:Constraints.Boo"],
            "Nested": ["Model:Constraints.Boo", "Model.Element:Constraints.Foo"],
            "Deep": ["Model:Constraints.Boo", "Model.Element:Constraints.Boo", "Model.Element.Element:Constraints.Foo"],
            "Inherited": ["Self:Constraints.Foo", "Self:Constraints.Boo"],
            "Refined": ["Self:Constraints.Nested", "Model.Element:Constraints.Boo"],
            "ClassOnly": [], "Plain": []
        ]
        for (name, expectedRequirements) in expected {
            let owner = try #require(forward.declarationsByID.values.first { $0.name == name && $0.kind == .protocol })
            let requirements = forward.protocolRequirements.filter { $0.protocolID == owner.id }
            let actual = requirements.map { requirement in
                let path = requirement.associatedTypePath.map { $0.children[0].description }.joined(separator: ".")
                return "\(path.isEmpty ? "Self" : path):\(requirement.requiredProtocol.description)"
            }
            #expect(Set(actual) == expectedRequirements, "\(name)")
        }
        let refined = try #require(forward.declarationsByID.values.first { $0.name == "Refined" })
        #expect(forward.members(of: refined.id).isEmpty)
        let before = requirementSnapshot(forward)
        for input in inputs {
            let result = try forward.merge(input)
            #expect(result.affectedDeclarationIDs.isEmpty)
            #expect(result.diagnostics.isEmpty)
        }
        #expect(requirementSnapshot(forward) == before)
    }

    @Test func mergesLinkerAliasesAndPreservesValueSemantics() throws {
        for fixture in ProtocolRequirementFixture.allCases {
            var store = SymbolIndexStore()
            try store.merge(fixture.input)
            let saved = store
            var copied = store
            let normalized = String(fixture.input.dropFirst())
            let result = try copied.merge(normalized)
            let requirement = try #require(copied.protocolRequirements.first)
            #expect(requirement.mangledSymbols == [fixture.input, normalized])
            #expect(result.affectedDeclarationIDs.contains(requirement.protocolID))
            #expect(saved.protocolRequirements.first?.mangledSymbols == [fixture.input])
            #expect(store.protocolRequirements.first?.mangledSymbols == [fixture.input])
            #expect(copied.symbolRecordsByMangledName.count == 1)
        }
    }

    @Test func retainsUnqualifiedAndDifferentlyQualifiedPaths() throws {
        let tree = try SwiftSymbol(ProtocolRequirementFixture.nested.input).children[0]
        var unqualified = tree
        unqualified.children[1].children[0].children.removeLast()
        let extraction = try SymbolExtractor().extract(unqualified, mangledSymbol: "unqualified")
        let requirement = try #require(extraction.protocolRequirements.first)
        #expect(requirement.associatedTypePath[0].children.count == 1)
        #expect(extraction.declarations.map(\.name) == ["Nested"])
        var differentlyQualified = tree
        differentlyQualified.children[1].children[1].children[1].children[0].children[0] = SwiftSymbol(kind: .module, contents: .name("OtherModule"))
        let first = try #require(SymbolExtractor().extract(tree, mangledSymbol: "first").protocolRequirements.first)
        let second = try #require(SymbolExtractor().extract(differentlyQualified, mangledSymbol: "second").protocolRequirements.first)
        #expect(first.structuralIdentity != second.structuralIdentity)
    }

    @Test func rejectsMalformedRequirements() throws {
        for fixture in MalformedProtocolRequirementFixture.allCases {
            #expect(throws: SymbolExtractor.ExtractionError.self) {
                try SymbolExtractor().extract(fixture.input, mangledSymbol: "malformed")
            }
        }
    }

    @Test func retainsUnsupportedRequirementTypesWithoutPartialFacts() throws {
        var tree = try SwiftSymbol(ProtocolRequirementFixture.nested.input).children[0]
        tree.children[2].children[0] = SwiftSymbol(kind: .structure, children: tree.children[2].children[0].children)
        let extraction = try SymbolExtractor().extract(tree, mangledSymbol: "unsupported")
        #expect(extraction.record.role == .unsupported)
        #expect(extraction.declarations.isEmpty)
        #expect(extraction.protocolRequirements.isEmpty)
        #expect(extraction.diagnostics.count == 1)
    }
}

private func requirementSnapshot(_ index: SymbolIndexStore) -> [[String]] {
    index.protocolRequirements.map {
        $0.structuralIdentity + [$0.mangledSymbols.sorted().joined(separator: ",")]
    }
}
