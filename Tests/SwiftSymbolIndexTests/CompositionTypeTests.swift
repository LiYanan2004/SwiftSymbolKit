import SwiftParser
import SwiftDemangle
import SwiftSyntax
import Testing
@testable import SwiftSymbolIndexStore

struct CompositionTypeTests {
    @Test func formatsAndParsesCompositionInTypeContexts() throws {
        let protocols = ["First", "Second"].map { name in
            SwiftSymbol(kind: .type, children: [SwiftSymbol(kind: .protocol, children: [
                SwiftSymbol(kind: .module, contents: .name("Example")),
                SwiftSymbol(kind: .identifier, contents: .name(name))
            ])])
        }
        let node = SwiftSymbol(kind: .protocolList, children: [SwiftSymbol(kind: .typeList, children: protocols)])
        let composition = try InterfaceTypeRenderer().type(node).formatted().description
        #expect(composition == "Example.First & Example.Second")
        for fixture in CompositionTypeFixture.allCases {
            #expect(!Parser.parse(source: fixture.source(composition)).hasError)
        }
    }
}

private enum CompositionTypeFixture: CaseIterable {
    case property, argument, genericArgument, metatype

    func source(_ composition: String) -> String {
        switch self {
        case .property: return "var value: \(composition) { get }"
        case .argument: return "func consume(_: \(composition)) {}"
        case .genericArgument: return "typealias Value = Optional<\(composition)>"
        case .metatype: return "typealias Value = (\(composition)).Type"
        }
    }
}
