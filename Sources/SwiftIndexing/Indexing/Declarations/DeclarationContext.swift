import SwiftDemangle

/// The lexical context of a declaration, distinct from types referenced in its signature.
public indirect enum DeclarationContext: Sendable {
    case module(String)
    case declaration(SymbolDeclaration.ID)
    case typeExtension(ExtensionContext)

    /// Groups extension members by declaring module, extended type and requirements.
    /// Original source extension blocks may not be recoverable from mangling.
    public struct ExtensionContext: Sendable {
        public let moduleName: String
        public let extendedType: SymbolDeclaration.ID
        public let genericSignature: SwiftSymbol?

        package init(moduleName: String, extendedType: SymbolDeclaration.ID, genericSignature: SwiftSymbol?) {
            self.moduleName = moduleName
            self.extendedType = extendedType
            self.genericSignature = genericSignature
        }
    }
}
