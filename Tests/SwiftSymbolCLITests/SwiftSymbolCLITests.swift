import Foundation
import SwiftIndexing
import Testing
@testable import SwiftSymbolCLI

@Suite
struct SwiftSymbolCLITests {
    @Test
    func exportedSwiftSymbols() throws {
        for fixture in TextBasedStubFixture.allCases {
            let stub = try TextBasedStub(yaml: fixture.input)
            #expect(stub.swiftSymbols == fixture.expectedSymbols)
        }
    }

    @Test
    func retainsSymbolTargetCoverage() throws {
        let arm = IndexingTarget(architecture: .arm64, platform: .macOS)
        let intel = IndexingTarget(architecture: .x86_64, platform: .macOS)
        let stub = try TextBasedStub(yaml: TextBasedStubFixture.multipleArchitectures.input)
        #expect(stub.targets == [arm, intel])
        #expect(stub.swiftSymbolTargets == [
            "_$s7Example3FooV": [arm, intel],
            "_$s7Example3BarV": [arm, intel],
            "_$s7Example3BazV": [arm, intel],
            "_$s7Example3QuxV": [arm],
        ])
        let weakSymbols = try TextBasedStub(yaml: TextBasedStubFixture.multipleArchitectures.input
            .replacingOccurrences(of: "weak-def-symbols:", with: "weak-symbols:"))
        #expect(weakSymbols.swiftSymbolTargets == stub.swiftSymbolTargets)
    }

    @Test
    func rejectsInvalidTargetCoverage() {
        let input = TextBasedStubFixture.multipleArchitectures.input
        for targets in ["[ arm64-ios ]", "[]"] {
            let invalid = input.replacingOccurrences(of: "targets: [ arm64-macos ]", with: "targets: " + targets)
            #expect(throws: (any Error).self) { try TextBasedStub(yaml: invalid) }
        }
        let missing = TextBasedStubFixture.empty.input
            .replacingOccurrences(of: "targets: [ arm64-macos ]", with: "")
        #expect(throws: (any Error).self) { try TextBasedStub(yaml: missing) }
    }

    @Test
    func normalizesLegacySimulatorTargets() throws {
        let input = TextBasedStubFixture.legacy.input.replacingOccurrences(of: "platform: macosx", with: "platform: ios")
        let stub = try TextBasedStub(yaml: input)
        let targets: Set<IndexingTarget> = [
            .init(architecture: .arm64, platform: .iOS),
            .init(architecture: .x86_64, platform: .iOS, environment: .simulator),
        ]
        #expect(stub.targets == targets)
        #expect(stub.swiftSymbolTargets.values.allSatisfy { $0 == targets })
    }

    @Test
    func rejectsMalformedStub() {
        #expect(throws: (any Error).self) {
            try TextBasedStub(yaml: "install-name: Example\nexports: [")
        }
        #expect(throws: (any Error).self) {
            try TextBasedStub(yaml: "unrelated: document")
        }
    }

    @Test
    func commandArguments() throws {
        let path = "/tmp/Example With Spaces.tbd"
        let parsedCommand = try SwiftSymbolCommand.parseAsRoot([
            "interface", path, "--module-name", "Example", "--compiler-version", "Swift version 6.0",
            "--output", "/tmp/Example.swiftinterface",
            "--target", "arm64-apple-macosx15.0", "--swift-version", "6", "--enable-library-evolution",
            "--import", "Swift", "--import", "Foundation", "--compiler-flag", "-D", "--compiler-flag", "TEST",
            "--interface-format-version", "1.0",
        ])
        let command = try #require(parsedCommand as? SwiftInterfaceCommand)
        #expect(command.input == URL(fileURLWithPath: path))
        #expect(command.moduleName == "Example")
        #expect(command.compilerVersion == "Swift version 6.0")
        #expect(command.output == "/tmp/Example.swiftinterface")
        #expect(command.target == "arm64-apple-macosx15.0")
        #expect(command.swiftVersion == "6")
        #expect(command.enableLibraryEvolution)
        #expect(command.imports == ["Swift", "Foundation"])
        #expect(command.otherCompilerFlags == ["-D", "TEST"])
        #expect(command.interfaceFormatVersion == "1.0")
        let fileCommand = try SwiftInterfaceCommand.parse([URL(fileURLWithPath: path).absoluteString])
        #expect(fileCommand.input == command.input)
        let remoteCommand = try SwiftInterfaceCommand.parse(["https://example.com/Example.tbd"])
        #expect(remoteCommand.input.scheme == "https")
        #expect(throws: (any Error).self) { try SwiftInterfaceCommand.parse(["ftp://example.com/test.tbd"]) }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SWIFT_INTERFACE_TEST_TBD"] != nil))
    func sdkStub() throws {
        let path = try #require(ProcessInfo.processInfo.environment["SWIFT_INTERFACE_TEST_TBD"])
        let stub = try TextBasedStub(yaml: String(contentsOfFile: path, encoding: .utf8))
        #expect(!stub.swiftSymbols.isEmpty)
        #expect(stub.swiftSymbols.count == Set(stub.swiftSymbols).count)
        print("Decoded \(stub.installName): \(stub.swiftSymbols.count) unique Swift symbols")
    }

    @Test
    func writesInterfaceFromTBD() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("Example.tbd")
        let output = directory.appendingPathComponent("Example.swiftinterface")
        try TextBasedStubFixture.multipleArchitectures.input.write(to: input, atomically: true, encoding: .utf8)
        var command = try SwiftInterfaceCommand.parse([
            input.path, "--output", output.path, "--import", "Swift",
            "--target", "arm64-apple-macosx15.0", "--compiler-flag", "-D", "--compiler-flag", "TEST",
        ])
        try await command.run()
        let text = try String(contentsOf: output, encoding: .utf8)
        #expect(text.contains("// swift-module-flags: -target arm64-apple-macosx15.0 -D TEST -module-name Example"))
        #expect(text.contains("import Swift"))
        for name in ["Foo", "Bar", "Baz", "Qux"] { #expect(text.contains("public struct \(name) {")) }
        #expect(!text.contains("Missing"))
    }
}
