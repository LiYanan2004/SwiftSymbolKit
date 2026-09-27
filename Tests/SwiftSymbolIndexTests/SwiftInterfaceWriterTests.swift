import Foundation
import Testing
import SwiftParser
import SwiftSyntax
@testable import SwiftSymbolIndexStore

private func diagnosticSnapshot(_ diagnostic: SymbolDiagnostic) -> [String] {
    [String(describing: diagnostic.kind), String(describing: diagnostic.severity),
     diagnostic.message, diagnostic.declarationID?.structuralKey ?? ""] + diagnostic.mangledSymbols.sorted()
}

struct SwiftInterfaceWriterTests {
    @Test func parallelInterfacesRemainDeterministic() async throws {
        for fixture in ParallelProcessingFixture.allCases {
            var store = SymbolIndexStore()
            try await store.merge(contentsOf: fixture.input)
            let writer = SwiftInterfaceWriter(configuration: .init(moduleName: "Example",
                compilerVersion: "test", imports: ["Swift", "Foundation"]))
            let expected = try await writer.write(store)
            for _ in 0..<3 {
                let output = try await writer.write(store)
                #expect(output.text == expected.text, "\(fixture)")
                #expect(output.diagnostics.map(diagnosticSnapshot) == expected.diagnostics.map(diagnosticSnapshot))
            }
        }
    }

    @Test func validatesIdentifierSpellings() throws {
        for fixture in InterfaceIdentifierFixture.allCases {
            if let expected = fixture.expected {
                #expect(try InterfaceTypeRenderer.identifier(fixture.input).text == expected)
            } else {
                #expect(throws: InterfaceTypeRenderer.RenderingError.self) {
                    try InterfaceTypeRenderer.identifier(fixture.input)
                }
            }
        }
    }

    @Test func generatedInterfacesParse() async throws {
        for fixture in SwiftInterfaceFixture.allCases where fixture != .unsupported {
            var store = SymbolIndexStore()
            for symbol in fixture.input { try store.merge(symbol) }
            let output = try await SwiftInterfaceWriter(configuration: .init(moduleName: fixture.moduleName,
                compilerVersion: "Swift test", imports: ["Swift", "Foundation.Submodule"])).write(store)
            let sourceFile = Parser.parse(source: output.text)
            #expect(!sourceFile.hasError, "\(fixture): \(output.text)")
            #expect(sourceFile.statements.prefix(2).allSatisfy { $0.item.is(ImportDeclSyntax.self) })
            #expect(!output.diagnostics.contains { $0.severity == .error }, "\(fixture)")
        }
    }

    @Test func reconstructsDeclarationsDeterministically() async throws {
        for fixture in SwiftInterfaceFixture.allCases {
            var forward = SymbolIndexStore()
            var reverse = SymbolIndexStore()
            for symbol in fixture.input { try forward.merge(symbol) }
            for symbol in fixture.input.reversed() { try reverse.merge(symbol) }
            let writer = SwiftInterfaceWriter(configuration: .init(moduleName: fixture.moduleName,
                header: .init(compilerVersion: "Swift test"), imports: ["Swift"]))
            let output = try await writer.write(forward)
            #expect(output.text == (try await writer.write(reverse).text), "\(fixture)")
            let normalizedText = output.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            for expected in fixture.expectedFragments {
                #expect(normalizedText.contains(expected.split(whereSeparator: \.isWhitespace).joined(separator: " ")),
                    "\(fixture): \(expected)\n\(output.text)")
            }
            for excluded in fixture.excludedFragments { #expect(!output.text.contains(excluded), "\(fixture): \(excluded)") }
            if fixture == .protocols {
                #expect(output.diagnostics.isEmpty)
            }
            if fixture == .genericMethodOnly {
                #expect(output.diagnostics.contains { $0.severity == .info && $0.message.contains("generic parameter names") })
            }
            if fixture == .unsupported {
                #expect(output.diagnostics.contains { $0.severity == .warning && $0.message.contains("Private or local declaration") })
                #expect(output.diagnostics.contains { $0.severity == .warning && $0.message.contains("opaque return type") })
                #expect(output.diagnostics.count == fixture.input.count)
                #expect(output.diagnostics.allSatisfy { !$0.mangledSymbols.isEmpty && $0.declarationID != nil })
            }
        }
    }

    @Test func rendersStorageWithIncompleteAccessorEvidence() async throws {
        for fixture in StorageInterfaceFixture.allCases {
            var store = SymbolIndexStore()
            for symbol in fixture.input { try store.merge(symbol) }
            let property = try #require(store.declarationsByID.values.first { $0.kind == .property })
            #expect(property.accessors == fixture.expectedAccessors)
            #expect(store.diagnostics.isEmpty)
            let writer = SwiftInterfaceWriter(configuration: .init(moduleName: "WidgetKit", compilerVersion: "test"))
            let output = try await writer.write(store)
            #expect(output.text.contains("extension SwiftUI.LabelStyle where Self == WidgetKit.AccessoryRectangularLabelStyle {"))
            #expect(output.text.split(whereSeparator: \.isWhitespace).joined(separator: " ").contains(fixture.expectedDeclaration))
            #expect(!output.text.contains("Unresolved declaration"))
            #expect(output.diagnostics.contains { $0.message.contains("reconstruction placeholder") } == fixture.expectsPlaceholder)
            #expect(store.declarationsByID[property.id]?.accessors == fixture.expectedAccessors)
            var reverse = SymbolIndexStore()
            for symbol in fixture.input.reversed() { try reverse.merge(symbol) }
            #expect(try await writer.write(reverse).text == output.text)
        }
    }

    @Test func headerModuleNameDoesNotFilterDeclarations() async throws {
        var store = SymbolIndexStore()
        let symbols = ["$s7Example6chooseyySiF", "$s5Other6chooseyySSF",
                       "$sSa5OtherE7inspectyyF", "$s7Example3FooVyxGAA14SampleProtocolAASQRzlMc"]
        for symbol in symbols { try store.merge(symbol) }
        let original = try await SwiftInterfaceWriter(configuration: .init(moduleName: "Example", compilerVersion: "test")).write(store)
        let renamed = try await SwiftInterfaceWriter(configuration: .init(moduleName: "MyExample", compilerVersion: "test")).write(store)
        #expect(original.text.replacingOccurrences(of: "-module-name Example", with: "-module-name MyExample") == renamed.text)
        #expect(renamed.text.contains("public func choose(_: Swift.Int)"))
        #expect(renamed.text.contains("public func choose(_: Swift.String)"))
        #expect(renamed.text.contains("extension Swift.Array"))
        #expect(renamed.text.contains("extension Example.Foo: Example.SampleProtocol"))
        #expect(!renamed.text.contains("public struct Array"))
    }

    @Test func retainsOpaqueViewExtensionSymbols() async throws {
        let symbols = ["_$s7SwiftUI4ViewP9WidgetKitE04hideC10OnSnapshotQryF",
                       "_$s7SwiftUI4ViewP9WidgetKitE04hideC10OnSnapshotQryFQOMQ"]
        var store = SymbolIndexStore()
        for symbol in symbols { try store.merge(symbol) }
        let output = try await SwiftInterfaceWriter(configuration: .init(moduleName: "MyWidgetKit", compilerVersion: "test")).write(store)
        #expect(output.text.contains("extension SwiftUI.View {"))
        #expect(output.text.contains("hideViewOnSnapshot"))
        #expect(output.text.contains("public func hideViewOnSnapshot() -> some"))
        #expect(!output.text.contains("public protocol View"))
        #expect(output.diagnostics.contains { $0.severity == .warning && $0.message.contains("opaque return type") })
    }

    @Test func selectsOnlyModuleTopLevelDeclarations() throws {
        var store = SymbolIndexStore()
        for symbol in SwiftInterfaceFixture.extensions.input + SwiftInterfaceFixture.declarations.input {
            try store.merge(symbol)
        }
        let declarations = store.declarations(inModule: "Example")
        #expect(Set(declarations.map(\.name)) == ["Foo", "labels", "Choice", "Object", "class"])
        #expect(declarations.map(\.id.structuralKey) == declarations.map(\.id.structuralKey).sorted())
        #expect(store.declarations(inModule: "Missing").isEmpty)
    }

    @Test func writesHeaderAndEscapesArguments() async throws {
        let writer = SwiftInterfaceWriter(configuration: .init(moduleName: "Example", header: .init(
            compilerVersion: "Swift test", compilerFlags: ["-target", "arm64-apple-macosx15.0", "-D", "A B",
                                                         "-D", "A\"B\\C", "-D", "", "-module-name", "Example"]
        ), imports: ["Swift", "Foundation", "Swift", "Example"]))
        let output = try await writer.write(SymbolIndexStore())
        #expect(output.text == """
        // swift-interface-format-version: 1.0
        // swift-compiler-version: Swift test
        // swift-module-flags: -target arm64-apple-macosx15.0 -D "A B" -D "A\\"B\\\\C" -D "" -module-name Example

        import Foundation
        import Swift

        """)
        #expect(output.diagnostics.isEmpty)
    }

    @Test func rejectsInvalidHeaderConfiguration() async {
        let configurations: [SwiftInterfaceWriter.Configuration] = [
            .init(moduleName: "Bad\nName", compilerVersion: "Swift"),
            .init(moduleName: "Example", compilerVersion: "Swift\nimport Bad"),
            .init(moduleName: "Example", compilerVersion: "Swift", compilerFlags: ["-module-name"]),
            .init(moduleName: "Example", compilerVersion: "Swift", compilerFlags: ["-module-name", "Other"]),
            .init(moduleName: "Example", compilerVersion: "Swift", compilerFlags: ["-module-name=Other"]),
            .init(moduleName: "Example", compilerVersion: "Swift", compilerFlags: ["-D", "A\nB"]),
            .init(moduleName: "Example", compilerVersion: "Swift", imports: ["Foundation\nimport Other"]),
        ]
        for configuration in configurations {
            await #expect(throws: (any Error).self) { try await SwiftInterfaceWriter(configuration: configuration).write(SymbolIndexStore()) }
        }
    }

    @Test func rendersSDKExports() async throws {
        let url = try #require(Bundle.module.url(forResource: "SwiftData.symbols", withExtension: "txt", subdirectory: "TestData"))
        let symbols = try String(contentsOf: url, encoding: .utf8).split(whereSeparator: \.isNewline).map(String.init)
        var store = SymbolIndexStore()
        for symbol in symbols { try store.merge(symbol) }
        let output = try await SwiftInterfaceWriter(configuration: .init(moduleName: "SwiftData", compilerVersion: "Swift test")).write(store)
        #expect(output.text.contains("public class ModelContext"))
        #expect(output.text.contains("public protocol PersistentModel"))
        #expect(output.text.contains("public class Schema"))
        #expect(!output.text.contains("fatalError"))
        #expect(!output.diagnostics.isEmpty)
    }
}
