import SwiftIndexing
import SwiftDemangle
import Testing
@_spi(Testing) @testable import SwiftSymbolIndexStore

struct RuntimeSymbolTests {
    @Test func extractsRuntimeSymbolsWithClassOwnership() throws {
        for fixture in RuntimeSymbolFixture.allCases {
            let extraction = try SymbolExtractor().extract(fixture.input)
            let runtime = try #require(extraction.runtimeSymbols.first)
            #expect(extraction.runtimeSymbols.count == 1)
            #expect(runtime.kind == fixture.expectedKind)
            #expect(runtime.mangledSymbols == [fixture.input])
            #expect(extraction.record.role == .auxiliary(fixture.expectedAuxiliaryKind))
            #expect(extraction.declarations.map(\.name) == fixture.expectedNames)
            #expect(extraction.declarations.last?.id == runtime.declarationID)
            #expect(extraction.declarations.allSatisfy { $0.evidence == .contextOnly })
            #expect(extraction.conformances.isEmpty)
            #expect(extraction.protocolRequirements.isEmpty)
            #expect(extraction.diagnostics.isEmpty)
        }
    }

    @Test func mergesAliasesPromotesClassesAndPreservesSnapshots() throws {
        for fixture in RuntimeSymbolFixture.allCases {
            var store = SymbolIndexStore()
            let result = try store.merge(fixture.input)
            let saved = store
            let runtime = try #require(saved.runtimeSymbols.first)
            #expect(result.affectedDeclarationIDs.contains(runtime.declarationID))
            let normalized = String(fixture.input.dropFirst())
            try store.merge(normalized)
            #expect(store.runtimeSymbols.count == 1)
            #expect(store.runtimeSymbols[0].mangledSymbols == [fixture.input, normalized])
            #expect(saved.runtimeSymbols[0].mangledSymbols == [fixture.input])
            #expect(store.symbolRecordsByMangledName.count == 1)
            let metadata = String(fixture.input.dropLast(2)) + "Mn"
            try store.merge(metadata)
            #expect(store.declarationsByID[runtime.declarationID]?.evidence == .direct)
            #expect(store.runtimeSymbols.count == 1)
            #expect(store.members(of: runtime.declarationID).isEmpty)
            let repeated = try store.merge(fixture.input)
            #expect(repeated.affectedDeclarationIDs.isEmpty)
            #expect(repeated.diagnostics.isEmpty)
        }
    }

    @Test func separatesRuntimeKindsAndKeepsNestedMembership() throws {
        let inputs = RuntimeSymbolFixture.allCases.map(\.input)
        var forward = SymbolIndexStore()
        var reverse = SymbolIndexStore()
        for input in inputs { try forward.merge(input) }
        for input in inputs.reversed() { try reverse.merge(input) }
        #expect(forward.runtimeSymbols.count == 4)
        #expect(Set(forward.runtimeSymbols.map(\.declarationID)).count == 2)
        #expect(forward.runtimeSymbols.map(\.structuralIdentity) == reverse.runtimeSymbols.map(\.structuralIdentity))
        #expect(forward.runtimeSymbols.map(\.mangledSymbols) == reverse.runtimeSymbols.map(\.mangledSymbols))
        let schema = try #require(forward.declarationsByID.values.first { $0.name == "Schema" })
        #expect(forward.members(of: schema.id).map(\.name) == ["Relationship"])
        #expect(forward.diagnostics.isEmpty)
    }

    @Test func rejectsMalformedLayoutsAndPreservesUnknownSymbols() throws {
        for kind in [SwiftSymbol.Kind.classMetadataBaseOffset, .methodLookupFunction] {
            for children in [[], [SwiftSymbol(kind: .type)], [SwiftSymbol(kind: .identifier)]] {
                #expect(throws: SymbolExtractor.ExtractionError.self) {
                    try SymbolExtractor().extract(SwiftSymbol(kind: kind, children: children), mangledSymbol: "invalid")
                }
            }
            let structure = try SwiftSymbol("$s7Example3FooV").children[0]
            let extraction = try SymbolExtractor().extract(
                SwiftSymbol(kind: kind, children: [SwiftSymbol(kind: .type, children: [structure])]),
                mangledSymbol: "unsupported")
            #expect(extraction.runtimeSymbols.isEmpty)
            #expect(extraction.declarations.isEmpty)
            #expect(extraction.record.role == .unsupported)
        }
        var store = SymbolIndexStore()
        let input = "$s7Example3FooVWOc"
        try store.merge(input)
        #expect(store.symbolRecordsByMangledName[input]?.mangledSymbols == [input])
        #expect(store.symbolRecordsByMangledName[input]?.role == .unsupported)
        #expect(store.runtimeSymbols.isEmpty)
    }
}

private enum RuntimeSymbolFixture: CaseIterable {
    case metadataOffset, lookupFunction, nestedMetadataOffset, nestedLookupFunction

    var input: String {
        switch self {
        case .metadataOffset: return "_$s9SwiftData12ModelContextCMo"
        case .lookupFunction: return "_$s9SwiftData12ModelContextCMu"
        case .nestedMetadataOffset: return "_$s9SwiftData6SchemaC12RelationshipCMo"
        case .nestedLookupFunction: return "_$s9SwiftData6SchemaC12RelationshipCMu"
        }
    }
    var expectedKind: RuntimeSymbolRecord.Kind {
        switch self {
        case .metadataOffset, .nestedMetadataOffset: return .classMetadataBaseOffset
        case .lookupFunction, .nestedLookupFunction: return .methodLookupFunction
        }
    }
    var expectedNames: [String] {
        switch self {
        case .metadataOffset, .lookupFunction: return ["ModelContext"]
        case .nestedMetadataOffset, .nestedLookupFunction: return ["Schema", "Relationship"]
        }
    }

    var expectedAuxiliaryKind: SwiftSymbol.Kind {
        switch self {
        case .metadataOffset, .nestedMetadataOffset: return .classMetadataBaseOffset
        case .lookupFunction, .nestedLookupFunction: return .methodLookupFunction
        }
    }
}
