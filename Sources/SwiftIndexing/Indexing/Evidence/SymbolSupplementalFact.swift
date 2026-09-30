/// One fact per field, so unrelated facts can be resolved independently.
/// Source fragments must be parsed and semantically validated before emission.
public enum SymbolSupplementalFact: Equatable, Sendable {
    public enum DefaultArgument: Equatable, Sendable {
        case expression(String)
        case expressionUnavailable
        case absent
    }
    
    public enum ImportKind: Equatable, Sendable {
        case explicit
        case implicit
        case exported
        case implementationOnly
    }
    
    case defaultArgument(parameterIndex: Int, value: DefaultArgument)
    case genericParameterName(depth: Int, index: Int, name: String)
    case modifier(name: String, isPresent: Bool)
    /// Compiler-verified storage needed to emit reference ownership modifiers.
    case storedProperty(isMutable: Bool)
    /// Fully qualified compiler spelling; nil records a class with no superclass.
    case superclass(typeName: String?)
    /// Effective case storage, including indirection inherited from its enum.
    /// Kept separate from the spelling of an explicit `indirect` modifier.
    case enumCaseIndirectStorage(isIndirect: Bool)
    /// A nil spelling records explicit absence. Missing evidence means unknown.
    case attribute(name: String, spelling: String?)
    /// Order is significant; an empty list records explicit absence.
    case primaryAssociatedTypes([String])
    /// Attached to an existing alias, or initially to its owner for a new alias.
    /// Reconciliation verifies its dependencies and indexes the alias as a declaration.
    case typeAlias(name: String, declaration: String)
    /// Runtime conformance witnesses are distinct from source-level typealiases.
    case associatedTypeWitness(protocolType: String, requirements: String?, name: String, type: String)
    case importedModule(name: String, kind: ImportKind)
    /// Attached to an existing Swift declaration to record its imported Objective-C name.
    case objectiveCName(String)
    /// Used to cross-check ABI facts; never replaces the mangled declaration's identity.
    case declarationSignature(String)
    case opaqueReturnType(OpaqueReturnType)
    /// Compiler-verified source spellings, keyed by the original Clang ABI identity.
    case clangTypeName(ClangTypeNameResolution)
}
