import SwiftDemangle

package extension SwiftSymbol {
    var declarationKind: SymbolDeclaration.Kind? {
        switch kind {
        case .structure: return .structure
        case .enum: return .enumeration
        case .class: return .class
        case .protocol: return .protocol
        case .typeAlias: return .typeAlias
        case .function: return .function
        case .allocator: return .initializer
        case .constructor: return .initializer
        case .destructor: return .deinitializer
        case .deallocator: return .deinitializer
        case .variable: return .property
        case .subscript: return .subscript
        default: return nil
        }
    }

    var accessorKind: SymbolDeclaration.AccessorKind? {
        switch kind {
        case .getter: return .getter
        case .globalGetter: return .getter
        case .setter: return .setter
        case .unsafeAddressor: return .unsafeAddressor
        case .unsafeMutableAddressor: return .unsafeMutableAddressor
        case .readAccessor: return .read
        case .read2Accessor, .yieldingBorrowAccessor: return .read
        case .modifyAccessor: return .modify
        case .modify2Accessor, .yieldingMutateAccessor: return .modify
        case .materializeForSet: return .materializeForSet
        case .willSet: return .willSet
        case .didSet: return .didSet
        case .initAccessor: return .initializer
        default: return nil
        }
    }

    /// Only wrappers whose single child identifies the represented declaration or conformance.
    var extractionRole: SymbolRecord.Role? {
        switch kind {
        case .typeMetadata: return .metadata
        case .typeMetadataAccessFunction: return .metadata
        case .fullTypeMetadata: return .metadata
        case .metaclass: return .metadata
        case .nominalTypeDescriptor: return .descriptor
        case .nominalTypeDescriptorRecord: return .descriptor
        case .protocolDescriptor: return .descriptor
        case .protocolDescriptorRecord: return .descriptor
        case .protocolRequirementsBaseDescriptor: return .descriptor
        case .methodDescriptor: return .descriptor
        case .propertyDescriptor: return .descriptor
        case .opaqueTypeDescriptor: return .descriptor
        case .opaqueReturnTypeOf: return .descriptor
        case .protocolConformanceDescriptor: return .descriptor
        case .protocolConformanceDescriptorRecord: return .descriptor
        case .dispatchThunk, .curryThunk, .protocolWitnessTable, .protocolWitnessTableAccessor:
            return .auxiliary(kind)
        default: return nil
        }
    }

    /// These global siblings annotate the following entity without changing its identity.
    var isEntityAttribute: Bool {
        switch kind {
        case .asyncFunctionPointer: return true
        case .coroFunctionPointer: return true
        case .defaultOverride: return true
        case .objCAttribute: return true
        case .nonObjCAttribute: return true
        case .dynamicAttribute: return true
        case .directMethodReferenceAttribute: return true
        default: return false
        }
    }

    /// Inspect only the outer generic scope. Nested function types own their own scopes.
    var declarationGenericSignature: SwiftSymbol? {
        if kind == .type, children.count == 1 {
            return children[0].declarationGenericSignature
        }
        guard kind == .dependentGenericType, children.count == 2,
              children[0].kind == .dependentGenericSignature else { return nil }
        return children[0]
    }

}
