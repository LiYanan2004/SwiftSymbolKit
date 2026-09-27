import SwiftDemangle

/// A protocol inheritance or associated-type conformance requirement observed in a symbol.
///
/// Descriptor symbols do not provide a complete protocol requirement signature: layout and same-type requirements can be absent from the exported symbol names.
public struct ProtocolConformanceRequirement {
    /// The protocol that declares this requirement.
    public let protocolID: SymbolDeclaration.ID

    /// An empty path denotes Self (protocol inheritance), otherwise each node is a `dependentAssociatedTypeRef`, retaining its name and optional declaring protocol. Keep the entire path to distinguish Model: P from Model.Element: P.
    public let associatedTypePath: [SwiftSymbol]
    public let requiredProtocol: SwiftSymbol
    public internal(set) var mangledSymbols: Set<String>

    internal var structuralIdentity: [String] {
        [protocolID.structuralKey, requiredProtocol.declarationKey] + associatedTypePath.map(\.declarationKey)
    }
}
