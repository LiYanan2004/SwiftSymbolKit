import Foundation
import SwiftIndexing
import Testing

struct IndexingContextTests {
    private let device = CompilerTarget(architecture: .arm64, platform: .iOS)
    private let authenticatedDevice = CompilerTarget(architecture: .arm64e, platform: .iOS)

    @Test func auxiliaryTargetsMustBeANonemptySubset() {
        let primary = IndexingContext(moduleName: "Example", targets: [device, authenticatedDevice])
        let auxiliary = IndexingContext(moduleName: "Example", targets: [device])
        #expect(auxiliary.isCompatible(with: primary))
        #expect(!primary.isCompatible(with: auxiliary))
        #expect(!IndexingContext(moduleName: "Example", targets: []).isCompatible(with: primary))
        #expect(!IndexingContext(moduleName: "Other", targets: [device]).isCompatible(with: primary))
        #expect(!IndexingContext(moduleName: "Example", targets: [
            .init(architecture: .arm64, platform: .iOS, environment: .simulator)
        ]).isCompatible(with: primary))
    }

    @Test func sdkIsComparedOnlyWhenBothSourcesProvideIt() {
        let unknown = IndexingContext(moduleName: "Example", targets: [device])
        let first = IndexingContext(moduleName: "Example", targets: [device], sdkIdentifier: "sdk-a")
        let second = IndexingContext(moduleName: "Example", targets: [device], sdkIdentifier: "sdk-b")
        #expect(unknown.isCompatible(with: first))
        #expect(first.isCompatible(with: unknown))
        #expect(first.isCompatible(with: first))
        #expect(!first.isCompatible(with: second))
    }

    @Test func targetSpellingsNormalizeWithoutLosingEnvironment() throws {
        #expect(try CompilerTarget(parsing: "arm64-apple-ios26.2") == device)
        #expect(try CompilerTarget(parsing: "arm64-ios") == device)
        #expect(try CompilerTarget(parsing: "arm64e-ios") != device)
        #expect(try CompilerTarget(parsing: "arm64-ios-simulator") ==
            CompilerTarget(parsing: "arm64-apple-ios26.2-simulator"))
        #expect(try CompilerTarget(parsing: "arm64-maccatalyst") ==
            CompilerTarget(parsing: "arm64-apple-ios26.2-macabi"))
        #expect(try CompilerTarget(parsing: "arm64-apple-macosx15.0") ==
            CompilerTarget(architecture: .arm64, platform: .macOS))
        #expect(try CompilerTarget(parsing: "arm64-ios-simulator") != device)
        #expect(try CompilerTarget(parsing: "arm64-maccatalyst") != device)
    }

    @Test(arguments: [CompilerTarget.Architecture.arm64_x1, .arm64e_x1], ["macos", "apple-macosx27.0"])
    func x1TargetsPreserveTheirArchitecture(architecture: CompilerTarget.Architecture, suffix: String) throws {
        let value = "\(architecture.rawValue)-\(suffix)"
        let target = CompilerTarget(architecture: architecture, platform: .macOS)
        #expect(try CompilerTarget(parsing: value) == target)
        let encoded = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(CompilerTarget.self, from: encoded) == target)
        #expect(try JSONDecoder().decode(CompilerTarget.Architecture.self,
            from: JSONEncoder().encode(architecture.rawValue)) == architecture)
        let context = IndexingContext(moduleName: "Example", targets: [target])
        for otherArchitecture: CompilerTarget.Architecture in [.arm64, .arm64e, .arm64_x1, .arm64e_x1] where otherArchitecture != architecture {
            let other = IndexingContext(moduleName: "Example", targets: [.init(architecture: otherArchitecture, platform: .macOS)])
            #expect(!context.isCompatible(with: other))
            #expect(!other.isCompatible(with: context))
        }
    }

    @Test(arguments: ["unknown-ios", "arm64-unknown", "arm64-ios-invalid", "arm64-macos-simulator", "arm64-ios26..2"])
    func unsupportedTargetsFail(value: String) {
        #expect(throws: CompilerTarget.ParsingError.self) { try CompilerTarget(parsing: value) }
    }
}
