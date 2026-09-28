import SwiftDemangle

/// A protocol inheritance or associated-type conformance requirement observed in a symbol.
///
/// Descriptor symbols do not provide a complete protocol requirement signature: layout and same-type requirements can be absent from the exported symbol names.
public struct ProtocolConformanceRequirement: Sendable {
    /// The protocol that declares this requirement.
    public let protocolID: SymbolDeclaration.ID

    /// An empty path denotes Self (protocol inheritance), otherwise each node is a `dependentAssociatedTypeRef`, retaining its name and optional declaring protocol. Keep the entire path to distinguish Model: P from Model.Element: P.
    public let associatedTypePath: [SwiftSymbol]
    public let requiredProtocol: SwiftSymbol
    public package(set) var mangledSymbols: Set<String>


    package init(protocolID: SymbolDeclaration.ID, associatedTypePath: [SwiftSymbol],
                 requiredProtocol: SwiftSymbol, mangledSymbols: Set<String>) {
        self.protocolID = protocolID
        self.associatedTypePath = associatedTypePath
        self.requiredProtocol = requiredProtocol
        self.mangledSymbols = mangledSymbols
    }
}
