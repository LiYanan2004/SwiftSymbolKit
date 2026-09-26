/// A read-only snapshot of declarations, relationships and their source symbols.
public struct SymbolIndex {
    public internal(set) var declarations: [SymbolDeclaration.ID: SymbolDeclaration] = [:]
    public internal(set) var symbols: [String: SymbolRecord] = [:]
    public internal(set) var conformances: [SymbolConformance] = []
    public internal(set) var diagnostics: [SymbolDiagnostic] = []

    internal init() {}

    public func declarations(inModule moduleName: String) -> [SymbolDeclaration] {
        // TODO: Return this module's top-level declarations in deterministic order.
        // Keep foreign type references separate from declarations owned by this module.
        fatalError("Module declaration lookup is not implemented")
    }

    public func members(of declarationID: SymbolDeclaration.ID) -> [SymbolDeclaration] {
        // TODO: Use a parent-to-members index to return immediate members, including
        // nested types and extension members. Preserve each member's extension context.
        fatalError("Declaration member lookup is not implemented")
    }
}
