import Testing
@testable import SwiftSymbolIndexStore

struct DefaultArgumentTests {
    @Test func retainsAuxiliarySymbolsWithoutInterfaceDeclarations() async throws {
        for fixture in DefaultArgumentFixture.allCases {
            var store = SymbolIndexStore()
            let result = try store.merge(fixture.input)
            let record = try #require(store.symbolRecordsByMangledName[String(fixture.input.dropFirst())])
            #expect(record.role == .auxiliary(.defaultArgumentInitializer))
            #expect(record.mangledSymbols == [fixture.input])
            #expect(record.demangledSymbol.children.first?.kind == .defaultArgumentInitializer)
            #expect(record.declarationIDs.isEmpty)
            #expect(result.affectedDeclarationIDs.isEmpty)
            #expect(store.declarationsByID.isEmpty)
            #expect(store.runtimeSymbols.isEmpty)
            #expect(store.diagnostics.isEmpty)
            let output = try await SwiftInterfaceWriter(configuration: .init(moduleName: "WidgetKit", compilerVersion: "test")).write(store)
            #expect(!output.text.contains(fixture.input))
            #expect(!output.text.contains("Symbols without a recoverable source declaration"))
            #expect(output.diagnostics.isEmpty)
            #expect(try store.merge(fixture.input).affectedDeclarationIDs.isEmpty)
        }
    }
}
