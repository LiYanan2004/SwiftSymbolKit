//
//  SymbolEvidenceSubject.swift
//  SwiftSymbolKit
//
//  Created by Yanan Li on 2026/9/28.
//


/// An unresolved reference. Source signatures require semantic matching, including
/// overloads, generic constraints, extension context and typealias expansion.
public enum SymbolEvidenceSubject: Sendable {
    case declaration(SymbolDeclaration.ID)
    /// Enum case names are unique within their structurally identified owner.
    case enumCase(owner: SymbolDeclaration.ID, name: String)
    case mangledSymbol(String)
    case sourceDeclaration(moduleName: String, context: [String], signature: String, usr: String?)
    case module(String)
}
