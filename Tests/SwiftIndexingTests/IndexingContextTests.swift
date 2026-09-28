import SwiftIndexing
import Testing

struct IndexingContextTests {
    private let device = IndexingTarget(architecture: .arm64, platform: .iOS)
    private let authenticatedDevice = IndexingTarget(architecture: .arm64e, platform: .iOS)

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
        #expect(try IndexingTarget(parsing: "arm64-apple-ios26.2") == device)
        #expect(try IndexingTarget(parsing: "arm64-ios") == device)
        #expect(try IndexingTarget(parsing: "arm64e-ios") != device)
        #expect(try IndexingTarget(parsing: "arm64-ios-simulator") ==
            IndexingTarget(parsing: "arm64-apple-ios26.2-simulator"))
        #expect(try IndexingTarget(parsing: "arm64-maccatalyst") ==
            IndexingTarget(parsing: "arm64-apple-ios26.2-macabi"))
        #expect(try IndexingTarget(parsing: "arm64-apple-macosx15.0") ==
            IndexingTarget(architecture: .arm64, platform: .macOS))
        #expect(try IndexingTarget(parsing: "arm64-ios-simulator") != device)
        #expect(try IndexingTarget(parsing: "arm64-maccatalyst") != device)
    }

    @Test(arguments: ["unknown-ios", "arm64-unknown", "arm64-ios-invalid", "arm64-macos-simulator", "arm64-ios26..2"])
    func unsupportedTargetsFail(value: String) {
        #expect(throws: IndexingTarget.ParsingError.self) { try IndexingTarget(parsing: value) }
    }
}
