import Foundation
import SwiftIndexing
import Testing
@testable import SwiftSymbolIndexStore

struct ContextualKeywordTests {
    private let fixture = """
    open class Base {
        public required init() {}
        public init(value: Int) {}
        open func method() {}
        open class func typeMethod() {}
        public dynamic class func dynamicTypeMethod() {}
        public static func staticTypeMethod() {}
        open var computed: Int { get { 1 } set {} }
        open subscript(index: Int) -> Int { get { index } set {} }
        public dynamic func dynamicMethod() {}
        public dynamic var dynamicValue: Int { get { 1 } set {} }
        public lazy var lazyValue = 1
        public weak var weakReference: Base?
        public unowned var unownedReference: Base? = nil
        public unowned(unsafe) var unsafeReference: Base? = nil
        public unowned let immutableReference: Base? = nil
    }
    open class Derived: Base {
        public required init() { super.init() }
        public override init(value: Int) { super.init(value: value) }
        public convenience init(flag: Bool) { self.init() }
        open dynamic override func method() {}
        public dynamic override class func typeMethod() {}
        public dynamic override var computed: Int { get { 2 } set {} }
        public dynamic override subscript(index: Int) -> Int { get { index } set {} }
    }
    open class GenericBase<Element> {
        public init() {}
        open func genericMethod(_ value: Element) {}
    }
    public class GenericDerived<Element>: GenericBase<Element> {
        public override init() { super.init() }
        public dynamic override func genericMethod(_ value: Element) {}
    }
    public struct Value {
        public init() {}
        public mutating func change() {}
        public func inspect() {}
        public static func staticMethod() {}
        public lazy var lazyValue = 1
    }
    public enum State {
        case value
        public mutating func change() {}
    }
    public protocol MutationRequirement {
        mutating func change()
        func inspect()
    }
    """

    @Test func reconstructsAndCompilesContextualKeywords() async throws {
        let moduleName = "ContextualFixture"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("Fixture.swift")
        try fixture.write(to: input, atomically: true, encoding: .utf8)
        let library = directory.appendingPathComponent("libContextualFixture.dylib")
        let originalInterface = directory.appendingPathComponent("Original.swiftinterface")
        _ = try run(["swiftc", input.path, "-module-name", moduleName, "-enable-library-evolution",
            "-emit-library", "-emit-module", "-emit-module-path", directory.appendingPathComponent(moduleName + ".swiftmodule").path,
            "-emit-module-interface-path", originalInterface.path, "-o", library.path])
        let symbols = try run(["nm", "-gUj", library.path]).split(separator: "\n").map(String.init).filter { $0.hasPrefix("_$s") }
        #if arch(arm64)
        let targetTriple = "arm64-apple-macosx15.0"
        #else
        let targetTriple = "x86_64-apple-macosx15.0"
        #endif
        let context = IndexingContext(moduleName: moduleName, targets: [try CompilerTarget(parsing: targetTriple)])
        let sdkPath = try run(["--sdk", "macosx", "--show-sdk-path"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let compiler = try await DeclarationModifierSource(configuration: .init(sdkPath: sdkPath,
            targetTriple: targetTriple, importSearchPaths: [directory.path]), context: context).read()
        #expect(compiler.diagnostics.isEmpty, "\(compiler.diagnostics.map(\.message))")
        var store = SymbolIndexStore()
        try await store.ingest(MangledSymbolSource(exportedSymbols: symbols, context: context))
        let declarations = Set(store.declarationsByID.keys)
        let exports = store.exportedSymbols
        try store.merge(compiler)
        #expect(Set(store.declarationsByID.keys) == declarations)
        #expect(store.exportedSymbols == exports)
        let compilerVersionPrefix = "// swift-compiler-version: "
        let originalText = try String(contentsOf: originalInterface, encoding: .utf8)
        let version = String(try #require(originalText.split(separator: "\n").first {
            $0.hasPrefix(compilerVersionPrefix)
        }).dropFirst(compilerVersionPrefix.count))
        let writer = SwiftInterfaceWriter(configuration: .init(moduleName: moduleName, compilerVersion: version,
            compilerFlags: ["-enable-library-evolution", "-module-name", moduleName, "-sdk", sdkPath, "-target", targetTriple], imports: ["Swift"]))
        let output = try await writer.write(store)
        #expect(!output.diagnostics.contains { $0.severity == .error }, "\(output.diagnostics.map(\.message))")
        let text = output.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        #expect(text.contains("open class Base"))
        #expect(!text.contains("public open"))
        #expect(text.contains("open override dynamic func method"))
        #expect(text.contains("open class func typeMethod"))
        #expect(text.contains("public dynamic class func dynamicTypeMethod"))
        #expect(text.contains("public static func staticTypeMethod"))
        #expect(!text.contains("final static"))
        #expect(text.contains("public override dynamic class func typeMethod"))
        #expect(text.contains("public override dynamic var computed"))
        #expect(text.contains("public override dynamic subscript"))
        #expect(text.contains("public required init()"))
        #expect(text.contains("public override init(value:"))
        #expect(text.contains("public convenience init(flag:"))
        #expect(text.contains("public dynamic func dynamicMethod"))
        #expect(text.contains("public dynamic var dynamicValue"))
        #expect(text.contains("public weak var weakReference"))
        #expect(text.contains("public unowned var unownedReference"))
        #expect(text.contains("public unowned(unsafe) var unsafeReference"))
        #expect(text.contains("unowned let immutableReference"))
        #expect(text.contains("public mutating func change"))
        #expect(text.contains("mutating func change()"))
        #expect(!text.contains("mutating func inspect"))
        #expect(!text.contains("lazy var"))
        #expect(text.contains("mutating get"))
        let lazyProperty = try #require(store.declarationsByID.values.first { $0.name == "lazyValue" })
        #expect(store.resolvedFactsBySubject[.declaration(lazyProperty.id)]?.contains {
            $0.fact == .modifier(name: "lazy", isPresent: true)
        } == true)
        let generated = directory.appendingPathComponent("Generated.swiftinterface")
        try output.text.write(to: generated, atomically: true, encoding: .utf8)
        _ = try run(["swiftc", "-frontend", "-compile-module-from-interface", generated.path,
            "-module-name", moduleName, "-sdk", sdkPath, "-target", targetTriple,
            "-o", directory.appendingPathComponent("Generated.swiftmodule").path])

        // Contradictory observations withdraw the affected fields independently.
        let weakProperty = try #require(store.declarationsByID.values.first { $0.name == "weakReference" })
        let conflictingSource = SymbolEvidenceSource(kind: .compilerDump, location: "other", artifactIdentifier: "other",
            lineageIdentifier: "other", producer: "Swift test")
        let conflict = IndexingResult(source: conflictingSource, context: context, evidence: [.init(source: conflictingSource,
            subject: .declaration(weakProperty.id), fact: .modifier(name: "weak", isPresent: false), location: "weakReference")])
        try store.merge(conflict)
        #expect(store.resolvedFactsBySubject[.declaration(weakProperty.id)]?.contains {
            $0.fact == .modifier(name: "weak", isPresent: true)
        } == false)
        #expect(store.diagnostics.contains { $0.kind == .conflictingInformation && $0.declarationID == weakProperty.id })
        #expect(try await writer.write(store).text.contains("public unowned(unsafe) var unsafeReference"))

        let derivedClass = try #require(store.declarationsByID.values.first { $0.name == "Derived" && $0.kind == .class })
        try store.merge(.init(source: conflictingSource, context: context, evidence: [.init(source: conflictingSource,
            subject: .declaration(derivedClass.id), fact: .superclass(typeName: nil), location: "Derived")]))
        let unresolvedSuperclass = try await writer.write(store)
        #expect(unresolvedSuperclass.diagnostics.contains { $0.message.contains("Override requires a resolved superclass") })
        #expect(!unresolvedSuperclass.text.contains("open override dynamic func method"))

        let unsafeProperty = try #require(store.declarationsByID.values.first { $0.name == "unsafeReference" })
        try store.merge(.init(source: conflictingSource, context: context, evidence: [.init(source: conflictingSource,
            subject: .declaration(unsafeProperty.id), fact: .storedProperty(isMutable: false), location: "unsafeReference")]))
        let unresolvedStorage = try await writer.write(store)
        #expect(unresolvedStorage.diagnostics.contains { $0.message.contains("Reference ownership requires resolved property storage") })
        #expect(unresolvedStorage.text.contains("public unowned var unownedReference"))
        #expect(store.exportedSymbols == exports)
    }

    @Test func rejectsIncompatibleModifierSubjectsWithoutAddingExports() async throws {
        let context = IndexingContext(moduleName: "Fixture", targets: [try CompilerTarget(parsing: "arm64-macos")])
        var store = SymbolIndexStore()
        try await store.ingest(MangledSymbolSource(exportedSymbols: ["$s7Fixture5ValueV6changeyyF"], context: context))
        let function = try #require(store.declarationsByID.values.first { $0.kind == .function })
        let source = SymbolEvidenceSource(kind: .compilerDump, location: "fixture", artifactIdentifier: "fixture",
            lineageIdentifier: "fixture", producer: "Swift test")
        let observation = SymbolEvidence(source: source, subject: .declaration(function.id),
            fact: .modifier(name: "required", isPresent: true), location: "change")
        let exports = store.exportedSymbols
        try store.merge(.init(source: source, context: context, evidence: [observation]))
        #expect(store.resolvedFactsBySubject[.declaration(function.id)]?.isEmpty != false)
        #expect(store.diagnostics.contains { $0.kind == .incompleteDeclaration })
        #expect(store.exportedSymbols == exports)
    }

    @Test func preservesKnownKeywordsWhenCompilerFieldsAreUnknown() throws {
        let context = IndexingContext(moduleName: "Fixture", targets: [try CompilerTarget(parsing: "arm64-macos")])
        let source = SymbolEvidenceSource(kind: .compilerDump, location: "fixture", artifactIdentifier: "fixture",
            lineageIdentifier: "fixture", producer: "Swift test")
        let json = #"""
        {"ABIRoot":{"kind":"Root","name":"Fixture","children":[
          {"kind":"TypeDecl","declKind":"Struct","mangledName":"$s7Fixture5ValueV","children":[
            {"kind":"Function","declKind":"Func","mangledName":"$s7Fixture5ValueV6changeyyF","funcSelfKind":"FutureSelfKind"},
            {"kind":"Var","declKind":"Var","mangledName":"$s7Fixture5ValueV8propertySivp","ownership":99,"declAttributes":["Lazy"]}
          ]},
          {"kind":"TypeDecl","declKind":"Class","mangledName":"$s7Fixture4BaseC","children":[
            {"kind":"Constructor","declKind":"Constructor","mangledName":"$s7Fixture4BaseCACycfc","init_kind":"FutureInitializerKind","declAttributes":["Required"]}
          ]}
        ]}}
        """#
        let result = try DeclarationModifierSource.parse(Data(json.utf8), source: source, context: context)
        #expect(result.evidence.contains { $0.fact == .modifier(name: "lazy", isPresent: true) })
        #expect(result.evidence.contains { $0.fact == .modifier(name: "required", isPresent: true) })
        #expect(!result.evidence.contains {
            if case .modifier(let name, _) = $0.fact { return ["weak", "unowned", "unowned(unsafe)", "mutating", "convenience"].contains(name) }
            return false
        })
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics.first?.message.contains("99") == true)
    }

    private func run(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else { throw TestError.toolFailed(text) }
        return text
    }

    private enum TestError: Error { case toolFailed(String) }
}
