import SwiftDemangle

/// The lexical context of a declaration, distinct from types referenced in its signature.
public indirect enum ParsedDeclarationContext: Sendable {
    case module(String)
    case declaration(ParsedDeclaration.ID)
    case typeExtension(ExtensionContext)

    /// Groups extension members by declaring module, extended type and requirements.
    /// Original source extension blocks may not be recoverable from mangling.
    public struct ExtensionContext: Sendable {
        public let moduleName: String
        public let extendedType: ParsedDeclaration.ID
        public let genericSignature: SwiftSymbol?

        internal init(moduleName: String, extendedType: ParsedDeclaration.ID, genericSignature: SwiftSymbol?) {
            self.moduleName = moduleName
            self.extendedType = extendedType
            self.genericSignature = genericSignature
        }
    }
}
