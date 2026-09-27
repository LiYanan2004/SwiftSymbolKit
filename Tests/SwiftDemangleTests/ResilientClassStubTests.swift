import Testing
@testable import SwiftDemangle

struct ResilientClassStubTests {
    @Test func matchesUpstreamTypeChildLayout() throws {
        for fixture in ResilientClassStubFixture.allCases {
            let root = try SwiftSymbol(fixture.input)
            #expect(root.kind == .global)
            let stub = try #require(root.children.first)
            #expect(stub.kind == fixture.expectedKind)
            #expect(stub.children.count == 1)
            let type = try #require(stub.children.first)
            #expect(type.kind == .type)
            #expect(type.children.count == 1)
            #expect(type.children.first?.kind == .class)
            #expect(root.description == fixture.expectedDescription)
        }
    }

    @Test func rejectsMissingType() {
        #expect(throws: (any Error).self) { try SwiftSymbol("$sMs") }
        #expect(throws: (any Error).self) { try SwiftSymbol("$sMt") }
    }
}

private enum ResilientClassStubFixture: CaseIterable {
    case glue, secondGlue, fullStub

    var input: String {
        switch self {
        case .glue: return "_$s7SwiftUI0A6UIGlueCMs"
        case .secondGlue: return "_$s7SwiftUI0A7UIGlue2CMs"
        case .fullStub: return "_$s7SwiftUI0A6UIGlueCMt"
        }
    }

    var expectedKind: SwiftSymbol.Kind {
        self == .fullStub ? .fullObjCResilientClassStub : .objCResilientClassStub
    }

    var expectedDescription: String {
        switch self {
        case .glue: return "ObjC resilient class stub for SwiftUI.SwiftUIGlue"
        case .secondGlue: return "ObjC resilient class stub for SwiftUI.SwiftUIGlue2"
        case .fullStub: return "full ObjC resilient class stub for SwiftUI.SwiftUIGlue"
        }
    }
}
