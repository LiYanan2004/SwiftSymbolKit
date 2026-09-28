import SwiftDemangle

/// Lossless node representation for facts extracted from mangled symbols.
/// Kept in indexing results until dedicated signature/type models replace the tree.
public typealias DemangledNode = SwiftDemangle.SwiftSymbol
