import SwiftDemangle

/// A conformance relationship with its own declaring module and conditional requirements.
public struct ProtocolConformance: Sendable {
    public let conformingType: SwiftSymbol
    public let protocolType: SwiftSymbol
    public let moduleName: String
    public let genericSignature: SwiftSymbol?
    public package(set) var mangledSymbols: Set<String>

    package init(conformingType: SwiftSymbol, protocolType: SwiftSymbol, moduleName: String,
                 genericSignature: SwiftSymbol?, mangledSymbols: Set<String>) {
        self.conformingType = conformingType
        self.protocolType = protocolType
        self.moduleName = moduleName
        self.genericSignature = genericSignature
        self.mangledSymbols = mangledSymbols
    }
}
