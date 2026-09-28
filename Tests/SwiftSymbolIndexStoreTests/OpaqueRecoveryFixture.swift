import Foundation

/// Expected source and metadata for the compiler-generated native image.
enum OpaqueRecoveryFixture: String, CaseIterable {
    case simple, composition, external, superclass, multiple, sequence, member, generic, nested

    var expectedFragment: String {
        switch self {
        case .simple: return "func simple() -> some OpaqueFixtures.P"
        case .composition: return "func composition() -> some OpaqueFixtures.P & OpaqueFixtures.Q"
        case .external: return "func external() -> some Swift.Equatable"
        case .superclass: return "func superclass() -> some OpaqueFixtures.Base"
        case .multiple: return "func multiple() -> (some OpaqueFixtures.P, some OpaqueFixtures.Q)"
        case .sequence: return "func sequence<A>(_: A) -> some"
        case .member: return "func member() -> some OpaqueFixtures.Q"
        case .generic: return "-> some OpaqueFixtures.P"
        case .nested: return "func nested() -> some OpaqueFixtures.Q"
        }
    }

    var expectedDepth: Int {
        switch self {
        case .sequence, .member, .nested: return 1
        case .generic: return 2
        default: return 0
        }
    }

    static var sourceURL: URL {
        Bundle.module.url(forResource: "Fixture", withExtension: "swift", subdirectory: "TestData/OpaqueRecovery")!
    }
}
