/// Constraints and an optional implementation type read from an opaque descriptor.
/// The implementation type is evidence only; interface emission preserves `some`.
public struct OpaqueReturnType: Equatable, Sendable {
    public let ordinal: Int
    public let parameterDepth: Int
    public let constraints: [DemangledNode]
    /// Requirements on associated types are retained even when their original
    /// primary-associated-type syntax cannot be recovered from runtime metadata.
    public let sameTypeRequirements: [DemangledNode]
    public let underlyingType: DemangledNode?

    public init(ordinal: Int, parameterDepth: Int, constraints: [DemangledNode],
                sameTypeRequirements: [DemangledNode] = [], underlyingType: DemangledNode? = nil) {
        self.ordinal = ordinal
        self.parameterDepth = parameterDepth
        self.constraints = constraints
        self.sameTypeRequirements = sameTypeRequirements
        self.underlyingType = underlyingType
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.ordinal == rhs.ordinal && lhs.parameterDepth == rhs.parameterDepth
            && lhs.constraints.map(\.declarationKey) == rhs.constraints.map(\.declarationKey)
            && lhs.sameTypeRequirements.map(\.declarationKey) == rhs.sameTypeRequirements.map(\.declarationKey)
            && lhs.underlyingType?.declarationKey == rhs.underlyingType?.declarationKey
    }
}
