public enum SymbolDeclarationMatch: Sendable {
    case matched(SymbolResolvedSubject)
    case unmatched
    /// The policy must retain ambiguity instead of choosing the first overload.
    case ambiguous([SymbolResolvedSubject])
}
