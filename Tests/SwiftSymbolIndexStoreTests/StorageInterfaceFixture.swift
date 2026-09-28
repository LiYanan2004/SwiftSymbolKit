import SwiftIndexing
import SwiftSymbolIndexStore

/// Descriptor-only and incremental accessor evidence for source reconstruction.
enum StorageInterfaceFixture: CaseIterable {
    case descriptorOnly, getter, setter, modify

    var descriptor: String {
        "_$s7SwiftUI10LabelStyleP9WidgetKitAD020AccessoryRectangularcD0VRszrlE09accessoryH0AFvpZMV"
    }

    var input: [String] {
        let variable = String(descriptor.dropLast(4))
        switch self {
        case .descriptorOnly: return [descriptor]
        case .getter: return [descriptor, variable + "gZ"]
        case .setter: return [descriptor, variable + "sZ"]
        case .modify: return [descriptor, variable + "MZ"]
        }
    }

    var expectedAccessors: Set<SymbolDeclaration.AccessorKind> {
        switch self {
        case .descriptorOnly: return []
        case .getter: return [.getter]
        case .setter: return [.setter]
        case .modify: return [.modify]
        }
    }

    var expectedDeclaration: String {
        let accessors = self == .setter || self == .modify ? "get set" : "get"
        return "public static var accessoryRectangular: WidgetKit.AccessoryRectangularLabelStyle { \(accessors) }"
    }

    var expectsPlaceholder: Bool { self == .descriptorOnly || self == .setter }
}
