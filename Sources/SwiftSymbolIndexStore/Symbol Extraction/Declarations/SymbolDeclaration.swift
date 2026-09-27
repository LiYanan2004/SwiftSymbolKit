import SwiftDemangle

/// A declaration assembled from one or more exported symbols.
public struct SymbolDeclaration: Sendable {
    /// Structural identity, independent of merge order and printed spelling.
    public struct ID: Hashable, Sendable {
        // Length-prefixed node encoding includes context, discriminators and signature.
        // This key is an implementation detail, not a persistent serialization format.
        internal let structuralKey: String
    }

    public enum Kind: Sendable {
        // Nominal types.
        case structure
        case enumeration
        case `class`
        case `protocol`
        /// A named alias; exported symbols may not encode its underlying type.
        case typeAlias

        // Callable declarations.
        case function
        case initializer
        case deinitializer

        // Storage declarations.
        case property
        case `subscript`

        // Enum and protocol members.
        case enumCase
        case associatedType
    }

    public enum Evidence: Sendable {
        /// The declaration is known only through another declaration's context.
        case contextOnly
        /// At least one symbol directly describes the declaration.
        case direct
    }

    public enum AccessorKind: Hashable, Sendable {
        // Value access.
        case getter
        case setter

        // Direct storage address access.
        case unsafeAddressor
        case unsafeMutableAddressor

        // Coroutine access.
        case read
        case modify
        case materializeForSet

        // Property observers.
        case willSet
        case didSet

        // Initialization.
        case initializer
    }

    public let id: ID
    public internal(set) var kind: Kind
    public internal(set) var name: String
    /// Original named-declaration node, including operator fixity or private/local discriminators.
    /// Initializers, deinitializers and subscripts have no named-declaration node.
    public internal(set) var nameNode: SwiftSymbol?
    public internal(set) var context: DeclarationContext
    public internal(set) var evidence: Evidence
    public internal(set) var isStatic: Bool
    /// Structured demangle nodes retained until dedicated signature models are introduced.
    /// A missing signature means unknown, rather than a function with no parameters.
    public internal(set) var signature: SwiftSymbol?
    /// External labels from the declaration's label list. An empty list denotes unlabeled
    /// parameters; nil means no separate label list was encoded (including legacy manglings).
    public internal(set) var parameterLabels: [String]?
    /// Requirements belonging to this declaration's generic scope.
    public internal(set) var genericSignature: SwiftSymbol?
    /// Observed accessors; absence alone does not establish source-level mutability.
    public internal(set) var accessors: Set<AccessorKind>
    public internal(set) var mangledSymbols: Set<String>
}
