import Testing
@testable import SwiftDemangle

struct RetroactiveConformanceTests {
    @Test func attachesConformancesToBoundTypeLikeUpstream() throws {
        let root = try SwiftSymbol("_$s7SwiftUI17_ScrollableLayoutP18decelerationTarget13contentOffset015originalContentH08velocity4sizeSo7CGPointVSgAJ_AjA9_VelocityVySo6CGSizeVAOSQ12CoreGraphicsyHCg_GAOtFTj")
        let bound = try #require(findBoundType(in: root))
        #expect(bound.children.count == 3)
        #expect(bound.children[1].kind == .typeList)
        #expect(bound.children[2].kind == .typeList)
        #expect(bound.children[2].children.map(\.kind) == [.retroactiveConformance])
        #expect(allTypeWrappersHaveOneChild(root))
    }

    private func findBoundType(in node: SwiftSymbol) -> SwiftSymbol? {
        if node.kind == .boundGenericStructure, node.children.count == 3 { return node }
        return node.children.lazy.compactMap { findBoundType(in: $0) }.first
    }

    private func allTypeWrappersHaveOneChild(_ node: SwiftSymbol) -> Bool {
        (node.kind != .type || node.children.count == 1) && node.children.allSatisfy(allTypeWrappersHaveOneChild)
    }
}
