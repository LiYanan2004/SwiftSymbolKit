import SwiftDemangle
import SwiftSymbolIndexStore

/// Manglings emitted from Fixtures/Example.swift by Apple Swift 6.2.4.
/// Reproduce with swiftc -emit-library -module-name Example -enable-library-evolution,
/// then inspect exported names with nm -gUj and swift-demangle --expand.
enum SymbolExtractionFixture: CaseIterable {
    case nestedMethod
    case nestedMetadata
    case structureDescriptor
    case protocolDescriptor
    case associatedType
    case staticMethod
    case asyncMethod
    case genericMethod
    case initializer
    case deinitializer
    case getter
    case setter
    case modifyAccessor
    case staticGetter
    case subscriptGetter
    case enumCase
    case labeledFunction
    case parameterPack
    case typedThrows
    case ownership
    case opaqueReturn

    var input: String {
        switch self {
        case .nestedMethod: return "$s7Example3FooV3BooV5helloyyF"
        case .nestedMetadata: return "$s7Example3FooV3BooVMa"
        case .structureDescriptor: return "$s7Example3FooVMn"
        case .protocolDescriptor: return "$s7Example14SampleProtocolMp"
        case .associatedType: return "$s7Element7Example14SampleProtocolPTl"
        case .staticMethod: return "$s7Example3FooV5helloySSSiFZ"
        case .asyncMethod: return "$s7Example3FooV5hello5valueSiSS_tYaKF"
        case .genericMethod: return "$s7Example3FooV9transformyqd__qd__xXElF"
        case .initializer: return "$s7Example3FooV5valueACyxGx_tcfC"
        case .deinitializer: return "$s7Example6ObjectCfd"
        case .getter: return "$s7Example3FooV8computedSivg"
        case .setter: return "$s7Example3FooV8computedSivs"
        case .modifyAccessor: return "$s7Example3FooV8computedSivM"
        case .staticGetter: return "$s7Example3FooV5countSivgZ"
        case .subscriptGetter: return "$s7Example3FooVyxSicig"
        case .enumCase: return "$s7Example6ChoiceO5valueyACSicACmFWC"
        case .labeledFunction: return "$s7Example6labels_6secondySi_SitF"
        case .parameterPack: return "$s7Example8identityyxxQp_txxQpRvzlF"
        case .typedThrows: return "$s7Example7checkedyyAA7FailureOYKF"
        case .ownership: return "$s7Example8transferyS2SnF"
        case .opaqueReturn: return "$s7Example6opaqueQryF"
        }
    }

    var expectedNames: [String] {
        switch self {
        case .nestedMethod: return ["Foo", "Boo", "hello"]
        case .nestedMetadata: return ["Foo", "Boo"]
        case .structureDescriptor: return ["Foo"]
        case .protocolDescriptor: return ["SampleProtocol"]
        case .associatedType: return ["SampleProtocol", "Element"]
        case .staticMethod: return ["Foo", "hello"]
        case .asyncMethod: return ["Foo", "hello"]
        case .genericMethod: return ["Foo", "transform"]
        case .initializer: return ["Foo", "init"]
        case .deinitializer: return ["Object", "deinit"]
        case .getter: return ["Foo", "computed"]
        case .setter: return ["Foo", "computed"]
        case .modifyAccessor: return ["Foo", "computed"]
        case .staticGetter: return ["Foo", "count"]
        case .subscriptGetter: return ["Foo", "subscript"]
        case .enumCase: return ["Choice", "value"]
        case .labeledFunction: return ["labels"]
        case .parameterPack: return ["identity"]
        case .typedThrows: return ["checked"]
        case .ownership: return ["transfer"]
        case .opaqueReturn: return ["opaque"]
        }
    }

    var expectedKind: SymbolDeclaration.Kind {
        switch self {
        case .nestedMetadata: return .structure
        case .structureDescriptor: return .structure
        case .protocolDescriptor: return .protocol
        case .associatedType: return .associatedType
        case .initializer: return .initializer
        case .deinitializer: return .deinitializer
        case .getter: return .property
        case .setter: return .property
        case .modifyAccessor: return .property
        case .staticGetter: return .property
        case .subscriptGetter: return .subscript
        case .enumCase: return .enumCase
        default: return .function
        }
    }

    var expectedRole: SymbolRecord.Role {
        switch self {
        case .nestedMetadata: return .metadata
        case .structureDescriptor: return .descriptor
        case .protocolDescriptor: return .descriptor
        case .associatedType: return .descriptor
        case .getter: return .accessor
        case .setter: return .accessor
        case .modifyAccessor: return .accessor
        case .staticGetter: return .accessor
        case .subscriptGetter: return .accessor
        default: return .declaration
        }
    }

    var expectedAccessors: Set<SymbolDeclaration.Accessor> {
        switch self {
        case .getter: return [.getter]
        case .setter: return [.setter]
        case .modifyAccessor: return [.modify]
        case .staticGetter: return [.getter]
        case .subscriptGetter: return [.getter]
        default: return []
        }
    }

    var expectedLabels: [String]? {
        switch self {
        case .staticMethod: return []
        case .asyncMethod: return ["value"]
        case .genericMethod: return []
        case .initializer: return ["value"]
        case .subscriptGetter: return []
        case .enumCase: return []
        case .labeledFunction: return ["_", "second"]
        case .parameterPack: return []
        case .ownership: return []
        default: return nil
        }
    }

    var expectedSignatureKinds: Set<SwiftSymbol.Kind> {
        switch self {
        case .asyncMethod: return [.asyncAnnotation, .throwsAnnotation]
        case .genericMethod: return [.dependentGenericType, .dependentGenericParamType, .noEscapeFunctionType]
        case .parameterPack: return [.packExpansion, .dependentGenericParamPackMarker]
        case .typedThrows: return [.typedThrowsAnnotation]
        case .ownership: return [.owned]
        case .opaqueReturn: return [.opaqueReturnType]
        default: return []
        }
    }
}

enum SymbolIdentityFixture: CaseIterable {
    case metadata
    case accessors
    case initializer
    case deinitializer
    case methodDescriptor
    case asyncPointer
    case modernCoroutine
    case opaqueDescriptor

    var input: [String] {
        switch self {
        case .metadata:
            return ["$s7Example3FooVMa", "$s7Example3FooVMn", "$s7Example3FooV"]
        case .accessors:
            return ["$s7Example3FooV8computedSivg", "$s7Example3FooV8computedSivs", "$s7Example3FooV8computedSivM"]
        case .initializer:
            return ["$s7Example6ObjectCACycfC", "$s7Example6ObjectCACycfc", "$s7Example6ObjectCACycfCTq"]
        case .deinitializer:
            return ["$s7Example6ObjectCfD", "$s7Example6ObjectCfd"]
        case .methodDescriptor:
            return ["$s7Example14SampleProtocolP5helloyyFTq", "$s7Example14SampleProtocolP5helloyyFTj"]
        case .asyncPointer:
            return [SymbolExtractionFixture.asyncMethod.input, SymbolExtractionFixture.asyncMethod.input + "Tu"]
        case .modernCoroutine:
            return ["$s7Library1BC1iSivx", "$s7Library1BC1iSivxTwdTwc", "$s7Library1BC1iSivy"]
        case .opaqueDescriptor:
            return ["$s7Example6opaqueQryF", "$s7Example6opaqueQryFQOMQ"]
        }
    }
}
