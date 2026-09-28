import SwiftIndexing

/// A canonical declaration assembled from indexed source facts.
public struct SymbolDeclaration: Sendable {
    /// Structural identity, independent of merge order and printed spelling.
    public struct ID: Hashable, Sendable {
        // Length-prefixed node encoding includes context, discriminators and signature.
        // This key is an implementation detail, not a persistent serialization format.
        internal let structuralKey: String

        internal init(structuralKey: String) { self.structuralKey = structuralKey }
    }

    public typealias Kind = ParsedDeclaration.Kind

    public typealias Evidence = ParsedDeclaration.Evidence

    public typealias AccessorKind = ParsedDeclaration.AccessorKind

    public let id: ID
    public internal(set) var kind: Kind
    public internal(set) var name: String
    /// Original named-declaration node, including operator fixity or private/local discriminators.
    /// Initializers, deinitializers and subscripts have no named-declaration node.
    public internal(set) var nameNode: DemangledNode?
    public internal(set) var context: DeclarationContext
    public internal(set) var evidence: Evidence
    public internal(set) var isStatic: Bool
    /// Structured demangle nodes retained until dedicated signature models are introduced.
    /// A missing signature means unknown, rather than a function with no parameters.
    public internal(set) var signature: DemangledNode?
    /// External labels from the declaration's label list. An empty list denotes unlabeled
    /// parameters; nil means no separate label list was encoded (including legacy manglings).
    public internal(set) var parameterLabels: [String]?
    /// Requirements belonging to this declaration's generic scope.
    public internal(set) var genericSignature: DemangledNode?
    /// Observed accessors; absence alone does not establish source-level mutability.
    public internal(set) var accessors: Set<AccessorKind>
    public internal(set) var mangledSymbols: Set<String>

    internal init(id: ID, kind: Kind, name: String, nameNode: DemangledNode?, context: DeclarationContext,
                 evidence: Evidence, isStatic: Bool, signature: DemangledNode?, parameterLabels: [String]?,
                 genericSignature: DemangledNode?, accessors: Set<AccessorKind>, mangledSymbols: Set<String>) {
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
