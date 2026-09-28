/// Adapters read their own artifact metadata before returning normalized input.
/// The index validates the returned context before applying any contribution.
public protocol IndexingSource: Sendable {
    func read() async throws -> IndexingResult
}

/// Information requested from a supplemental reader. Readers may also return
/// related observations encountered during extraction for local verification.
public enum SupplementalInformation: Hashable, Sendable {
    case typeAliases
    case defaultArguments
    case genericParameterNames
    case modifiersAndAttributes
    case primaryAssociatedTypes
    case imports
    case objectiveCNames
    case associatedTypeWitnesses
}
