/// A source-level Swift path, including the owning module and nested types.
public struct SwiftTypeName: Hashable, Sendable {
    public let moduleName: String
    public let pathComponents: [String]
    
    public init(moduleName: String, pathComponents: [String]) {
        self.moduleName = moduleName
        self.pathComponents = pathComponents
    }
    
    public var qualifiedName: String { ([moduleName] + pathComponents).joined(separator: ".") }
}

/// A candidate whose complete parameter ABI identity was checked with SwiftDemangle.
public struct ClangTypeName: Hashable, Sendable {
    public let identity: ClangTypeIdentity
    public let swiftName: SwiftTypeName
    public let requiredImport: String
    public let clangUSR: String
    public let declarationKind: String
    public let probeSymbol: String
    
    package init(identity: ClangTypeIdentity, swiftName: SwiftTypeName, requiredImport: String,
                 clangUSR: String, declarationKind: String, probeSymbol: String) {
        self.identity = identity
        self.swiftName = swiftName
        self.requiredImport = requiredImport
        self.clangUSR = clangUSR
        self.declarationKind = declarationKind
        self.probeSymbol = probeSymbol
    }
}

public struct ClangTypeNameResolution: Equatable, Sendable {
    public enum Status: Equatable, Sendable { case resolved, unresolved, ambiguous }
    
    public let identity: ClangTypeIdentity
    /// Includes equivalent aliases as evidence even when a nominal spelling is preferred.
    public let candidates: [ClangTypeName]
    
    package init(identity: ClangTypeIdentity, candidates: [ClangTypeName]) {
        self.identity = identity
        self.candidates = Array(Set(candidates)).sorted {
            [$0.swiftName.qualifiedName, $0.clangUSR, $0.probeSymbol, $0.declarationKind, $0.requiredImport]
                .lexicographicallyPrecedes([$1.swiftName.qualifiedName, $1.clangUSR, $1.probeSymbol, $1.declarationKind, $1.requiredImport])
        }
    }
    
    private var preferredNames: Set<SwiftTypeName> {
        let nominal = candidates.filter { $0.declarationKind != "swift.typealias" }
        return Set((nominal.isEmpty ? candidates : nominal).map(\.swiftName))
    }
    
    public var status: Status {
        switch preferredNames.count {
            case 0: return .unresolved
            case 1: return .resolved
            default: return .ambiguous
        }
    }
    
    public var swiftName: SwiftTypeName? {
        preferredNames.count == 1 ? preferredNames.first : nil
    }
}
