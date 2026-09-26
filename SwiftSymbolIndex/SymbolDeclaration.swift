import SwiftDemangle

/// A declaration assembled from one or more exported symbols.
public struct SymbolDeclaration {
    /// Structural identity, independent of merge order and printed spelling.
    public struct ID: Hashable {
        // Length-prefixed node encoding includes context, discriminators and signature.
        // This key is an implementation detail, not a persistent serialization format.
        internal let structuralKey: String
    }

    public enum Kind {
        // Nominal types.
        case structure
        case enumeration
        case `class`
        case `protocol`

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

    public enum Evidence {
        /// The declaration is known only through another declaration's context.
        case contextOnly
        /// At least one symbol directly describes the declaration.
        case direct
    }

    public enum Accessor: Hashable {
        // Value access.
        case getter
        case setter

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
    public internal(set) var accessors: Set<Accessor>
    public internal(set) var mangledSymbols: Set<String>
}
