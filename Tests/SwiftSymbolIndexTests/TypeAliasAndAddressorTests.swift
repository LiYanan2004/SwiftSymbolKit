import SwiftDemangle
import SwiftParser
import Testing
@testable import SwiftSymbolIndexStore

struct TypeAliasAndAddressorTests {
    @Test func indexesAliasExtensionMembers() async throws {
        for fixture in TypeAliasFixture.allCases {
            var store = SymbolIndexStore()
            try store.merge(fixture.input)
            let alias = try #require(store.declarationsByID.values.first { $0.kind == .typeAlias })
            #expect(alias.name == fixture.aliasName)
            #expect(alias.evidence == .contextOnly)
            let member = try #require(store.members(of: alias.id).first)
            #expect(member.name == fixture.memberName)
            #expect(member.evidence == .direct)
            #expect(store.diagnostics.isEmpty)
            let output = try await SwiftInterfaceWriter(configuration: .init(moduleName: "SwiftUI", compilerVersion: "test")).write(store)
            #expect(output.text.contains("extension __C.\(fixture.aliasName)"))
            #expect(output.text.contains(fixture.memberName))
            #expect(!output.text.contains("typealias"))
            #expect(!output.diagnostics.contains { $0.severity == .error })
            #expect(!Parser.parse(source: output.text).hasError)
        }
    }

    @Test func retainsUnknownAliasTarget() async throws {
        var store = SymbolIndexStore()
        try store.merge("$sSo10AGGraphRefa")
        #expect(store.declarationsByID.values.first?.kind == .typeAlias)
        let output = try await SwiftInterfaceWriter(configuration: .init(moduleName: "Example", compilerVersion: "test")).write(store)
        #expect(output.diagnostics.contains { $0.message == "Unresolved declaration: Type alias underlying type is unavailable" })
        #expect(!output.text.contains("typealias AGGraphRef ="))
    }

    @Test func mergesAndRendersAddressorEvidence() async throws {
        for fixture in AddressorFixture.allCases {
            var store = SymbolIndexStore()
            try await store.merge(contentsOf: fixture.input)
            let declaration = try #require(store.declarationsByID.values.first { $0.kind == .subscript })
            #expect(declaration.accessors == fixture.expectedAccessors)
            #expect(store.diagnostics.isEmpty)
            let writer = SwiftInterfaceWriter(configuration: .init(moduleName: "SwiftUI", compilerVersion: "test"))
            let output = try await writer.write(store)
            #expect(!output.diagnostics.contains { $0.severity == .error })
            #expect(!Parser.parse(source: output.text).hasError)
            #expect(output.text.contains("unsafeAddress"))
            #expect(output.text.contains("-> \(fixture.expectedElementType)"))
            #expect(output.text.contains("unsafeMutableAddress") == fixture.expectedAccessors.contains(.unsafeMutableAddressor))
            #expect(!output.diagnostics.contains { $0.message.contains("no readable accessor") })
            #expect(output.diagnostics.contains { $0.message.contains("mutating/nonmutating") })
            var reverse = SymbolIndexStore()
            try await reverse.merge(contentsOf: fixture.input.reversed())
            #expect(try await writer.write(reverse).text == output.text)
        }
    }
}

private enum TypeAliasFixture: CaseIterable {
    case function, property, initializer
    var input: String {
        switch self {
        case .function: return "_$sSo10AGGraphRefa7SwiftUIE11stopTracingyyFZ"
        case .property: return "_$sSo10CGImageRefa7SwiftUIE4sizeSo6CGSizeVvg"
        case .initializer: return "_$sSo6RBUUIDa7SwiftUIE4hashAbC10StrongHashV_tcfC"
        }
    }
    var aliasName: String {
        switch self {
        case .function: return "AGGraphRef"
        case .property: return "CGImageRef"
        case .initializer: return "RBUUID"
        }
    }
    var memberName: String {
        switch self {
        case .function: return "stopTracing"
        case .property: return "size"
        case .initializer: return "init"
        }
    }
}

private enum AddressorFixture: CaseIterable {
    case buffer, pointer, mutablePointer, mixedAccessors
    var input: [String] {
        switch self {
        case .buffer:
            return ["_$s7SwiftUI36UnsafeMutableBufferProjectionPointerVyq_Sicilu", "_$s7SwiftUI36UnsafeMutableBufferProjectionPointerVyq_Siciau"]
        case .pointer: return ["_$sSP7SwiftUIExycilu"]
        case .mutablePointer: return ["_$sSp7SwiftUIExycilu", "_$sSp7SwiftUIExyciau"]
        case .mixedAccessors:
            return ["g", "s", "lu", "au"].map { "_$s10Addressors6BufferVyxSici" + $0 }
        }
    }
    var expectedAccessors: Set<SymbolDeclaration.AccessorKind> {
        switch self {
        case .pointer: return [.unsafeAddressor]
        case .buffer, .mutablePointer: return [.unsafeAddressor, .unsafeMutableAddressor]
        case .mixedAccessors: return [.getter, .setter, .unsafeAddressor, .unsafeMutableAddressor]
        }
    }

    var expectedElementType: String {
        switch self {
        case .buffer: return "B"
        case .pointer, .mutablePointer, .mixedAccessors: return "A"
        }
    }
}
