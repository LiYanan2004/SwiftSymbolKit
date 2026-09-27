import SwiftDemangle

enum AuxiliarySymbolFixture: CaseIterable {
    case protocolWitness, fieldOffset, initializer, propertyWrapperBackingInitializer
    case classStub, fullClassStub

    var input: String {
        switch self {
        case .protocolWitness:
            return "_$s7SwiftUI012GestureStateC0Vyxq_GAA0C0A2aEP4body4BodyQzvgTW"
        case .fieldOffset:
            return "_$s7Example3FooV5valueSivpWvd"
        case .initializer:
            return "_$s10Foundation16AttributedStringV7SwiftUIE10UTF16CacheV16_utf16Characters33_68688E58AD1196635FA5905612EAD940LLs15ContiguousArrayVys6UInt16VGvpfi"
        case .propertyWrapperBackingInitializer:
            return "_$s7SwiftUI11LocationBoxC5cache33_3C10A6E9BB0D4644A364890A9BD57D68LLAA0C15ProjectionCacheVvpfP"
        case .classStub: return "_$s7SwiftUI0A6UIGlueCMs"
        case .fullClassStub: return "_$s7SwiftUI0A6UIGlueCMt"
        }
    }

    var expectedKind: SwiftSymbol.Kind {
        switch self {
        case .protocolWitness: return .protocolWitness
        case .fieldOffset: return .fieldOffset
        case .initializer: return .initializer
        case .propertyWrapperBackingInitializer: return .propertyWrapperBackingInitializer
        case .classStub: return .objCResilientClassStub
        case .fullClassStub: return .fullObjCResilientClassStub
        }
    }
}
