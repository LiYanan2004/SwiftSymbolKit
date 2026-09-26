import Foundation
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
        ])
        let command = try #require(parsedCommand as? SwiftInterfaceCommand)
        #expect(command.input == URL(fileURLWithPath: path))
        #expect(command.moduleName == "Example")
        #expect(command.compilerVersion == "Swift version 6.0")
        #expect(command.output == "/tmp/Example.swiftinterface")
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
}
