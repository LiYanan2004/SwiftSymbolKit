import Testing
@testable import SwiftDemangle

struct ConstrainedExistentialTests {
    @Test func matchesUpstreamRequirementLayoutAndOrder() throws {
        for fixture in ConstrainedExistentialFixture.allCases {
            let root = try SwiftSymbol(fixture.input)
            let existential = try #require(findExistential(in: root))
            #expect(existential.children.count == 2)
            #expect(existential.children[0].kind == .type)
            #expect(existential.children[1].kind == .constrainedExistentialRequirementList)
            let requirements = existential.children[1].children
            #expect(requirements.count == fixture.associatedTypes.count)
            for (requirement, name) in zip(requirements, fixture.associatedTypes) {
                #expect(requirement.kind == .dependentGenericSameTypeRequirement)
                #expect(requirement.children.count == 2)
                let member = try #require(requirement.children.first?.children.first)
                #expect(member.kind == .dependentMemberType)
                #expect(member.children.first?.children.first?.kind == .constrainedExistentialSelf)
                #expect(member.children.last?.children.first?.text == name)
            }
        }
    }

    private func findExistential(in node: SwiftSymbol) -> SwiftSymbol? {
        if node.kind == .constrainedExistential { return node }
        return node.children.lazy.compactMap { findExistential(in: $0) }.first
    }
}

private enum ConstrainedExistentialFixture: CaseIterable {
    case sequence, asyncIterator
    var input: String {
        switch self {
        case .sequence: return "_$s7SwiftUI28BreadthFirstSearchEvaluationO8continueyACyxq_GST_px7ElementRts_XPcAEmr0_lFWC"
        case .asyncIterator: return "_$s10AppIntents26_AsyncIntentItemCollectionVyACyxq_GScI_px7ElementRts_q_7FailureRtsXPAA01_cdE15IteratorOptionsVccfC"
        }
    }
    var associatedTypes: [String] {
        switch self {
        case .sequence: return ["Element"]
        case .asyncIterator: return ["Element", "Failure"]
        }
    }
}
