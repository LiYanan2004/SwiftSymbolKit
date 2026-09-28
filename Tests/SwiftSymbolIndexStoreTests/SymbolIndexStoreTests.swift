import SwiftIndexing
import Foundation
import SwiftDemangle
import Testing
@_spi(Testing) @testable import SwiftSymbolIndexStore

struct SymbolIndexStoreTests {
    @Test func parallelMergesMatchIncrementalMerges() async throws {
        for fixture in ParallelProcessingFixture.allCases {
            let inputs = try fixture.input
            let expected = snapshot(try mergedStore(inputs))
            var store = SymbolIndexStore()
            try await store.merge(contentsOf: inputs)
            #expect(snapshot(store) == expected, "\(fixture)")
            try await store.merge(contentsOf: inputs.reversed())
            #expect(snapshot(store) == expected)
        }
    }

    @Test func parallelFailuresPreserveTheInputPrefix() async throws {
        for fixture in ParallelFailureFixture.allCases {
            var store = SymbolIndexStore()
            do {
                try await store.merge(contentsOf: fixture.input)
                Issue.record("Expected the first invalid symbol to fail")
            } catch let error as SymbolIndexStore.MergeError {
                #expect(error.mangledSymbol == fixture.invalidSymbol)
            }
            #expect(snapshot(store) == snapshot(try mergedStore(fixture.validPrefix)))
            // The store remains usable after a failed batch.
            try store.merge(SymbolExtractionFixture.getter.input)
            #expect(store.symbolRecordsByMangledName[SymbolExtractionFixture.getter.input] != nil)
        }
    }

    @Test func cancelledBulkMergePreservesExistingSymbols() async throws {
        let initial = try mergedStore([SymbolExtractionFixture.getter.input])
        let task = Task {
            var store = initial
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                try await store.merge(contentsOf: ParallelProcessingFixture.largeType.input)
                Issue.record("Expected cancellation to stop extraction")
            } catch is CancellationError {
                return snapshot(store)
            }
            return snapshot(store)
        }
        #expect(try await task.value == snapshot(initial))
    }

    @Test func startsEmpty() {
        let index = SymbolIndexStore()
        #expect(index.declarationsByID.isEmpty)
        #expect(index.symbolRecordsByMangledName.isEmpty)
        #expect(index.conformances.isEmpty)
        #expect(index.protocolRequirements.isEmpty)
        #expect(index.runtimeSymbols.isEmpty)
        #expect(index.diagnostics.isEmpty)
        #expect(index.members(of: .init(structuralKey: "unknown")).isEmpty)
    }

    @Test func mergesEveryDeclarationKindAndPreservesFacts() throws {
        for fixture in SymbolExtractionFixture.allCases {
            var store = SymbolIndexStore()
            let extraction = try SymbolExtractor().extract(fixture.input)
            let result = try store.merge(fixture.input)
            #expect(result.diagnostics.isEmpty, "\(fixture)")
            #expect(result.affectedDeclarationIDs == Set(extraction.declarations.map(\.id)))
            #expect(store.declarationsByID.count == fixture.expectedNames.count)
            #expect(store.symbolRecordsByMangledName[fixture.input]?.role == fixture.expectedRole)
            for declaration in extraction.declarations {
                let merged = try #require(store.declarationsByID[declaration.id])
                #expect(declarationSnapshot(merged) == declarationSnapshot(declaration))
            }
            #expect(try store.merge(fixture.input).affectedDeclarationIDs.isEmpty)
            #expect(store.symbolRecordsByMangledName.count == 1)
        }
    }

    @Test func combinesRelatedSymbolsInEitherOrder() throws {
        for fixture in SymbolIdentityFixture.allCases {
            let forward = try mergedStore(fixture.input)
            let reverse = try mergedStore(fixture.input.reversed())
            #expect(snapshot(forward) == snapshot(reverse), "\(fixture)")
            let extraction = try SymbolExtractor().extract(fixture.input[0])
            let identifier = try #require(extraction.declarations.last?.id)
            let declaration = try #require(forward.declarationsByID[identifier])
            #expect(declaration.mangledSymbols == Set(fixture.input))
            #expect(forward.declarationsByID.count == extraction.declarations.count)
            #expect(forward.diagnostics.isEmpty)
        }
    }

    @Test func unionsEveryStorageAccessor() throws {
        for fixture in StorageMergeFixture.allCases {
            let store = try mergedStore(fixture.input)
            let declaration = try #require(store.declarationsByID.values.first { $0.kind == fixture.expectedKind })
            #expect(declaration.accessors == fixture.expectedAccessors, "\(fixture)")
            #expect(declaration.mangledSymbols == Set(fixture.input))
            #expect(store.declarationsByID.count == 2)
            #expect(store.diagnostics.isEmpty)
        }
    }

    @Test func promotesAncestorsAndMaintainsImmediateMembers() throws {
        var store = SymbolIndexStore()
        let input = SymbolExtractionFixture.nestedMethod.input
        try store.merge(input)
        let outer = try #require(store.declarationsByID.values.first { $0.name == "Foo" })
        let nested = try #require(store.declarationsByID.values.first { $0.name == "Boo" })
        #expect(outer.evidence == .contextOnly)
        #expect(nested.evidence == .contextOnly)
        #expect(store.members(of: outer.id).map(\.name) == ["Boo"])
        #expect(store.members(of: nested.id).map(\.name) == ["hello"])
        let result = try store.merge(SymbolExtractionFixture.nestedMetadata.input)
        #expect(result.affectedDeclarationIDs == [outer.id, nested.id])
        #expect(store.declarationsByID[nested.id]?.evidence == .direct)
        #expect(store.declarationsByID[outer.id]?.evidence == .contextOnly)
        try store.merge(SymbolExtractionFixture.structureDescriptor.input)
        #expect(store.declarationsByID[outer.id]?.evidence == .direct)
        let laterMember = "$s7Example3FooV3BooV7goodbyeyyF"
        try store.merge(laterMember)
        #expect(store.declarationsByID[nested.id]?.evidence == .direct)
        #expect(store.declarationsByID[outer.id]?.evidence == .direct)
        #expect(Set(store.members(of: nested.id).map(\.name)) == ["hello", "goodbye"])
        #expect(store.members(of: outer.id).count == 1)
    }

    @Test func retainsExtensionOwnershipAndRequirements() throws {
        let inputs = ["$sSa7ExampleAA14SampleProtocolRzlE7inspectyyF",
                      "$sSa7ExampleE7inspectyyF", "$sSa5OtherE7inspectyyF"]
        let store = try mergedStore(inputs)
        let array = try #require(store.declarationsByID.values.first { $0.name == "Array" })
        let members = store.members(of: array.id)
        #expect(members.count == 3)
        #expect(array.evidence == .contextOnly)
        #expect(array.genericSignature == nil)
        var modules: Set<String> = []
        var requirementCount = 0
        for member in members {
            guard case .typeExtension(let context) = member.context else {
                Issue.record("Expected an extension context")
                continue
            }
            modules.insert(context.moduleName)
            requirementCount += context.genericSignature == nil ? 0 : 1
            #expect(context.extendedType == array.id)
            #expect(member.genericSignature == nil)
        }
        #expect(modules == ["Example", "Other"])
        #expect(requirementCount == 1)
    }

    @Test func distinguishesOverloadsContextsLabelsAndStaticMembers() throws {
        for fixture in DistinctDeclarationFixture.allCases {
            let store = try mergedStore(fixture.input)
            let direct = store.declarationsByID.values.filter { $0.evidence == .direct }
            #expect(direct.count == fixture.input.count, "\(fixture)")
            #expect(store.diagnostics.isEmpty, "\(fixture)")
            #expect(snapshot(store) == snapshot(try mergedStore(fixture.input.reversed())))
        }
    }

    @Test func normalizesLinkerPrefixesAndRetainsAllSpellings() throws {
        for fixture in LinkerSpellingFixture.allCases {
            let store = try mergedStore(fixture.input)
            let reverse = try mergedStore(fixture.input.reversed())
            #expect(store.symbolRecordsByMangledName.count == 1, "\(fixture)")
            let record = try #require(store.symbolRecordsByMangledName[fixture.normalized])
            #expect(record.mangledSymbol == fixture.normalized)
            #expect(record.mangledSymbols == Set(fixture.input))
            #expect(snapshot(store) == snapshot(reverse))
            for declaration in store.declarationsByID.values {
                #expect(declaration.mangledSymbols == Set(fixture.input))
            }
        }
    }

    @Test func mergesConformancesSeparately() throws {
        let conformance = "$s7Example3FooVyxGAA14SampleProtocolAASQRzl"
        let inputs = [conformance + "Mc", conformance + "WP", conformance + "Wa",
                      "$s7Example3FooVyxGAA14SampleProtocolAASHRzlMc",
                      "$s7Example3FooVyxGAA14SampleProtocol5OtherSQRzlMc",
                      "$s7Example3FooVyxGSQAASQRzlMc"]
        let store = try mergedStore(inputs)
        #expect(store.declarationsByID.isEmpty)
        #expect(store.conformances.count == 4)
        #expect(store.diagnostics.isEmpty)
        let combined = try #require(store.conformances.first { $0.mangledSymbols.count == 3 })
        #expect(combined.mangledSymbols == Set(inputs.prefix(3)))
        #expect(combined.genericSignature != nil)
        #expect(Set(store.conformances.map(\.moduleName)) == ["Example", "Other"])
        #expect(snapshot(store) == snapshot(try mergedStore(inputs.reversed())))
    }

    @Test func retainsUnsupportedSymbolsAndDeduplicatesDiagnostics() throws {
        let inputs = ["$s7Example3FooVWOc", "$s7Example3FooV3BooV5helloyyF.1", "async_Main"]
        for input in inputs {
            var store = SymbolIndexStore()
            let result = try store.merge(input)
            #expect(result.affectedDeclarationIDs.isEmpty)
            #expect(result.diagnostics.count == 1)
            #expect(store.symbolRecordsByMangledName[input]?.role == .unsupported)
            #expect(store.declarationsByID.isEmpty)
            #expect(store.conformances.isEmpty)
            #expect(store.diagnostics.first?.mangledSymbols == [input])
            let prefixedResult = try store.merge("_" + input)
            #expect(prefixedResult.diagnostics.count == 1)
            #expect(store.diagnostics.count == 1)
            #expect(store.diagnostics.first?.mangledSymbols == [input, "_" + input])
            let before = snapshot(store)
            let duplicate = try store.merge(input)
            #expect(duplicate.affectedDeclarationIDs.isEmpty)
            #expect(duplicate.diagnostics.isEmpty)
            #expect(snapshot(store) == before)
        }
    }

    @Test func failuresLeaveExistingIndexUnchanged() throws {
        var store = try mergedStore([SymbolExtractionFixture.nestedMethod.input,
                                     "$s7Example3FooVWOc", "$s7Example3FooVAA14SampleProtocolAAWP"])
        let before = snapshot(store)
        for input in ["", "not a symbol", "$s", "_$s", "___$s7Example3FooV", "$s7Example3FooV8", "Si"] {
            #expect(throws: (any Error).self) { try store.merge(input) }
            #expect(snapshot(store) == before, "\(input)")
        }
    }

    @Test func preservesValueSemantics() throws {
        var original = try mergedStore([SymbolExtractionFixture.getter.input])
        let before = snapshot(original)
        let savedStore = original
        var copy = original
        try copy.merge(SymbolExtractionFixture.setter.input)
        try original.merge(SymbolExtractionFixture.modifyAccessor.input)
        #expect(snapshot(savedStore) == before)
        let originalProperty = try #require(original.declarationsByID.values.first { $0.kind == .property })
        let copiedProperty = try #require(copy.declarationsByID.values.first { $0.kind == .property })
        #expect(originalProperty.accessors == [.getter, .modify])
        #expect(copiedProperty.accessors == [.getter, .setter])
    }

    @Test func mergesSwiftDataExports() throws {
        let url = try #require(Bundle.module.url(forResource: "SwiftData.symbols", withExtension: "txt", subdirectory: "TestData"))
        let inputs = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
        var store = try mergedStore(inputs)
        #expect(inputs.count == 1588)
        #expect(store.symbolRecordsByMangledName.count == 1588)
        #expect(store.declarationsByID.count == 637)
        #expect(store.conformances.count == 129)
        #expect(store.protocolRequirements.count == 51)
        #expect(store.protocolRequirements.filter { $0.associatedTypePath.isEmpty }.count == 21)
        #expect(store.runtimeSymbols.count == 24)
        #expect(store.runtimeSymbols.filter { $0.kind == .classMetadataBaseOffset }.count == 12)
        #expect(store.runtimeSymbols.filter { $0.kind == .methodLookupFunction }.count == 12)
        #expect(Set(store.runtimeSymbols.map(\.declarationID)).count == 12)
        #expect(store.diagnostics.isEmpty)
        #expect(store.symbolRecordsByMangledName.values.allSatisfy { $0.role != .unsupported })
        #expect(Set(store.symbolRecordsByMangledName.values.flatMap(\.mangledSymbols)) == Set(inputs))
        let backingData = try #require(store.declarationsByID.values.first { $0.name == "BackingData" })
        let identifier = try #require(store.members(of: backingData.id).first { $0.name == "persistentModelID" })
        #expect(identifier.accessors == [.getter, .setter, .modify])
        #expect(identifier.mangledSymbols.count == 6)
        #expect(identifier.evidence == .direct)
        let history = try #require(store.declarationsByID.values.first { $0.name == "HistoryProviding" })
        #expect(store.members(of: history.id).contains { $0.name == "HistoryType" && $0.kind == .associatedType })
        let before = snapshot(store)
        for input in inputs {
            let result = try store.merge(input)
            #expect(result.affectedDeclarationIDs.isEmpty)
            #expect(result.diagnostics.isEmpty)
        }
        #expect(snapshot(store) == before)
        #expect(snapshot(try mergedStore(inputs.reversed())) == before)
    }
}

private func mergedStore(_ inputs: some Sequence<String>) throws -> SymbolIndexStore {
    var store = SymbolIndexStore()
    for input in inputs { try store.merge(input) }
    return store
}

private func declarationSnapshot(_ declaration: SymbolDeclaration) -> String {
    [declaration.id.structuralKey, String(describing: declaration.kind), declaration.name,
     treeSnapshot(declaration.nameNode), contextSnapshot(declaration.context),
     String(describing: declaration.evidence), String(declaration.isStatic),
     treeSnapshot(declaration.signature), String(describing: declaration.parameterLabels),
     treeSnapshot(declaration.genericSignature),
     declaration.accessors.map { String(describing: $0) }.sorted().joined(separator: ","),
     declaration.mangledSymbols.sorted().joined(separator: ",")].joined(separator: "\n")
}

private func contextSnapshot(_ context: DeclarationContext) -> String {
    switch context {
    case .module(let name): return "module:\(name)"
    case .declaration(let identifier): return "declaration:\(identifier.structuralKey)"
    case .typeExtension(let context):
        return "extension:\(context.moduleName):\(context.extendedType.structuralKey):\(treeSnapshot(context.genericSignature))"
    }
}

private func snapshot(_ index: SymbolIndexStore) -> [String] {
    let declarations = index.declarationsByID.values.map(declarationSnapshot).sorted()
    let records = index.symbolRecordsByMangledName.map { key, record in
        [key, record.mangledSymbol, treeSnapshot(record.demangledSymbol), String(describing: record.role),
         record.declarationIDs.map(\.structuralKey).sorted().joined(separator: ","),
         record.mangledSymbols.sorted().joined(separator: ",")].joined(separator: "\n")
    }.sorted()
    let conformances = index.conformances.map {
        [treeSnapshot($0.conformingType), treeSnapshot($0.protocolType), $0.moduleName,
         treeSnapshot($0.genericSignature), $0.mangledSymbols.sorted().joined(separator: ",")].joined(separator: "\n")
    }
    let diagnostics = index.diagnostics.map {
        [String(describing: $0.kind), $0.message, $0.declarationID?.structuralKey ?? "",
         $0.mangledSymbols.sorted().joined(separator: ",")].joined(separator: "\n")
    }
    let requirements = index.protocolRequirements.map {
        ([$0.protocolID.structuralKey, treeSnapshot($0.requiredProtocol)]
            + $0.associatedTypePath.map { treeSnapshot($0) }
            + [$0.mangledSymbols.sorted().joined(separator: ",")]).joined(separator: "\n")
    }
    let members = index.declarationsByID.keys.map { identifier in
        identifier.structuralKey + ":" + index.members(of: identifier).map { $0.id.structuralKey }.joined(separator: ",")
    }.sorted()
    let runtimeSymbols = index.runtimeSymbols.map {
        ($0.structuralIdentity + [$0.mangledSymbols.sorted().joined(separator: ",")]).joined(separator: "\n")
    }
    return declarations + records + conformances + requirements + runtimeSymbols + diagnostics + members
}

/// Compare retained trees without declaration-identity normalization or printer output.
private func treeSnapshot(_ symbol: SwiftSymbol?) -> String {
    guard let symbol else { return "nil" }
    let fields = [String(describing: symbol.kind), String(describing: symbol.contents)]
        + symbol.children.map { treeSnapshot($0) }
    return fields.map { "\($0.utf8.count):\($0)" }.joined()
}
