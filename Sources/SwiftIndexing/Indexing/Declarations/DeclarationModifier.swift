/// Modifiers supported by compiler semantic recovery and interface generation.
package enum DeclarationModifier: String, CaseIterable {
    case final, indirect, open, required, override, lazy, dynamic, convenience, weak, unowned
    case unownedUnsafe = "unowned(unsafe)"
    case mutating

    package func supports(_ declaration: SymbolDeclaration, ownerKind: SymbolDeclaration.Kind?) -> Bool {
        let isClassMember = ownerKind == .class
        let isOverridableMember = [.function, .property, .subscript].contains(declaration.kind)
        switch self {
        case .final, .open:
            return declaration.kind == .class || (isClassMember && isOverridableMember)
        case .indirect:
            return declaration.kind == .enumeration || declaration.kind == .enumCase
        case .required, .convenience:
            return isClassMember && declaration.kind == .initializer
        case .override:
            return isClassMember && (isOverridableMember || declaration.kind == .initializer)
        case .lazy, .weak, .unowned, .unownedUnsafe:
            return declaration.kind == .property
        case .dynamic:
            return isOverridableMember || declaration.kind == .initializer
        case .mutating:
            return declaration.kind == .function && !declaration.isStatic
                && ownerKind.map { [.structure, .enumeration, .protocol].contains($0) } == true
        }
    }
}
