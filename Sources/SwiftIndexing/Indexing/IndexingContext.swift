/// The identity and target coverage of a primary artifact or supplemental source.
public struct IndexingContext: Equatable, Sendable {
    public let moduleName: String
    public let targets: Set<CompilerTarget>
    public let sdkIdentifier: String?

    public init(moduleName: String, targets: Set<CompilerTarget>, sdkIdentifier: String? = nil) {
        self.moduleName = moduleName
        self.targets = targets
        self.sdkIdentifier = sdkIdentifier
    }

    public var isValid: Bool {
        !moduleName.isEmpty && !targets.isEmpty
    }

    /// Compatibility is directional: this context belongs to the supplemental source.
    public func isCompatible(with primaryContext: IndexingContext) -> Bool {
        guard isValid, primaryContext.isValid,
              moduleName == primaryContext.moduleName,
              targets.isSubset(of: primaryContext.targets) else { return false }
        if let sdkIdentifier, let primarySDKIdentifier = primaryContext.sdkIdentifier {
            return sdkIdentifier == primarySDKIdentifier
        }
        return true
    }
}
