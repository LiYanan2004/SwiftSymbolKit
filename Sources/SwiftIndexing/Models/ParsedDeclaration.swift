import SwiftDemangle

/// A declaration observed in a source, before matching into the canonical index.
public struct ParsedDeclaration: Sendable {
    /// A source reference. Mangled input uses a structural key; other inputs require semantic matching.
    public struct ID: Hashable, Sendable {
        // Length-prefixed node encoding includes context, discriminators and signature.
        // This key is an implementation detail, not a persistent serialization format.
        package let structuralKey: String

        internal init(structuralKey: String) {
            self.structuralKey = structuralKey
        }
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
    public let kind: Kind
    public let name: String
    /// Original named-declaration node, including operator fixity or private/local discriminators.
    /// Initializers, deinitializers and subscripts have no named-declaration node.
    public let nameNode: SwiftSymbol?
    public let context: ParsedDeclarationContext
    public let evidence: Evidence
    public let isStatic: Bool
    /// Structured demangle nodes retained until dedicated signature models are introduced.
    /// A missing signature means unknown, rather than a function with no parameters.
    public let signature: SwiftSymbol?
    /// External labels from the declaration's label list. An empty list denotes unlabeled
    /// parameters; nil means no separate label list was encoded (including legacy manglings).
    public let parameterLabels: [String]?
    /// Requirements belonging to this declaration's generic scope.
    public let genericSignature: SwiftSymbol?
    /// Observed accessors; absence alone does not establish source-level mutability.
    public let accessors: Set<AccessorKind>
    public let mangledSymbols: Set<String>

    internal init(id: ID, kind: Kind, name: String, nameNode: SwiftSymbol?, context: ParsedDeclarationContext,
                 evidence: Evidence, isStatic: Bool, signature: SwiftSymbol?, parameterLabels: [String]?,
                 genericSignature: SwiftSymbol?, accessors: Set<AccessorKind>, mangledSymbols: Set<String>) {
        self.id = id
        self.kind = kind
        self.name = name
        self.nameNode = nameNode
        self.context = context
        self.evidence = evidence
        self.isStatic = isStatic
        self.signature = signature
        self.parameterLabels = parameterLabels
        self.genericSignature = genericSignature
        self.accessors = accessors
        self.mangledSymbols = mangledSymbols
    }
}
