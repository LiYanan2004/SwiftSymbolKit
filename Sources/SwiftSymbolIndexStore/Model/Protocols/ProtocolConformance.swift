import SwiftIndexing

/// A conformance relationship with its own declaring module and conditional requirements.
public struct ProtocolConformance: Sendable {
    public let conformingType: DemangledNode
    public let protocolType: DemangledNode
    public let moduleName: String
    public let genericSignature: DemangledNode?
    public internal(set) var mangledSymbols: Set<String>

    internal init(conformingType: DemangledNode, protocolType: DemangledNode, moduleName: String,
                 genericSignature: DemangledNode?, mangledSymbols: Set<String>) {
        self.conformingType = conformingType
        self.protocolType = protocolType
        self.moduleName = moduleName
        self.genericSignature = genericSignature
        self.mangledSymbols = mangledSymbols
    }
}
