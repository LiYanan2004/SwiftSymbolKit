/// The build environment shared by the export surface and supplemental evidence.
public struct IndexingContext: Equatable, Sendable {
    public let moduleName: String
    public let targetTriple: String
    /// A versioned SDK/build identity, rather than an SDK directory path.
    public let sdkIdentifier: String
    /// Ordered arguments affecting interpretation, including language mode, feature
    /// flags, conditional compilation and module search paths. Normalize at the caller.
    public let compilerArguments: [String]

    public init(moduleName: String, targetTriple: String, sdkIdentifier: String,
                compilerArguments: [String] = []) {
        self.moduleName = moduleName
        self.targetTriple = targetTriple
        self.sdkIdentifier = sdkIdentifier
        self.compilerArguments = compilerArguments
    }
}
