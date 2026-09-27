import SwiftDemangle

/// A conformance relationship with its own declaring module and conditional requirements.
public struct ProtocolConformance {
    public let conformingType: SwiftSymbol
    public let protocolType: SwiftSymbol
    public let moduleName: String
    public let genericSignature: SwiftSymbol?
    public internal(set) var mangledSymbols: Set<String>
}
