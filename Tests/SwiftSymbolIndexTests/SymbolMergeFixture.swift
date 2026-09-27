import SwiftSymbolIndexStore

/// Small, explicit inputs complement the complete SwiftData export fixture.
enum StorageMergeFixture: CaseIterable {
    case property
    case subscriptAccessors
    case staticProperty
    case coroutineVariants

    var input: [String] {
        switch self {
        case .property:
            return ["g", "s", "r", "M", "m", "w", "W", "i"].map { "$s7Example3FooV8computedSiv" + $0 }
        case .subscriptAccessors:
            return ["g", "s", "r", "M"].map { "$s7Example3FooVyxSici" + $0 }
        case .staticProperty:
            return ["g", "s", "M"].map { "$s7Example3FooV5countSiv" + $0 + "Z" }
        case .coroutineVariants:
            return ["r", "M", "x", "y"].map { "$s7Library1BC1iSiv" + $0 }
        }
    }

    var expectedKind: SymbolDeclaration.Kind {
        self == .subscriptAccessors ? .subscript : .property
    }

    var expectedAccessors: Set<SymbolDeclaration.AccessorKind> {
        switch self {
        case .property: return [.getter, .setter, .read, .modify, .materializeForSet, .willSet, .didSet, .initializer]
        case .subscriptAccessors: return [.getter, .setter, .read, .modify]
        case .staticProperty: return [.getter, .setter, .modify]
        case .coroutineVariants: return [.read, .modify]
        }
    }
}

enum DistinctDeclarationFixture: CaseIterable {
    case overloads
    case modules
    case labels
    case staticMembers
    case nestedContexts
    case extensions
    case propertyTypes
    case operatorFixity
    case privateDiscriminators
    case localDiscriminators

    var input: [String] {
        switch self {
        case .overloads:
            return ["$s7Example6chooseyySiF", "$s7Example6chooseyySSF", "$s7Example6chooseSiyF"]
        case .modules:
            return ["$s7Example6chooseyySiF", "$s5Other6chooseyySiF"]
        case .labels:
            return ["$s7Example6choose5firstySi_tF", "$s7Example6choose6secondySi_tF"]
        case .staticMembers:
            return ["$s7Example3FooV5countSivg", "$s7Example3FooV5countSivgZ"]
        case .nestedContexts:
            return ["$s7Example3FooV5helloyyF", "$s7Example3FooV3BooV5helloyyF"]
        case .extensions:
            return ["$s7Example3FooVAASQRzlE5helloyyF", "$s7Example3FooV5helloyyF"]
        case .propertyTypes:
            return ["$s7Example3FooV5valueSivg", "$s7Example3FooV5valueSSvg"]
        case .operatorFixity:
            return ["$s7Example1poiyyF", "$s7Example1popyyF", "$s7Example1poPyyF"]
        case .privateDiscriminators:
            return ["$s7Example5hello5_fileLLyyF", "$s7Example5hello6_otherLLyyF"]
        case .localDiscriminators:
            return ["$s7Example5helloL_yyF", "$s7Example5helloL0_yyF"]
        }
    }
}

enum LinkerSpellingFixture: CaseIterable {
    case stable
    case swift42
    case embedded
    case swift4
    case legacy
    case asyncEntryPoint

    var normalized: String {
        switch self {
        case .stable: return "$s7Example3FooV8computedSivg"
        case .swift42: return "$S7Example3FooV8computedSivg"
        case .embedded: return "$e7Example3FooV8computedSivg"
        case .swift4: return "_T07Example3FooV8computedSivg"
        case .legacy: return "_TFC3foo3bar3basfT3zimCS_3zim_T_"
        case .asyncEntryPoint: return "async_Main"
        }
    }

    var input: [String] { [normalized, "_" + normalized] }
}
