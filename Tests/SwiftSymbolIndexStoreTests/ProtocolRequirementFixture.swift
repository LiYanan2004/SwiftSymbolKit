import SwiftDemangle

enum ProtocolRequirementFixture: CaseIterable {
    case inheritance, composition, dependent, nested, deep, inheritedAssociatedType

    var input: String {
        switch self {
        case .inheritance: return "_$s11Constraints9InheritedPAA3FooTb"
        case .composition: return "_$s11Constraints11CompositionP5ModelAC_AA3FooTn"
        case .dependent: return "_$s11Constraints9DependentP3FooAC_AA3BooTn"
        case .nested: return "_$s11Constraints6NestedP5ModelAC_7ElementAA3BooPAA3FooTn"
        case .deep: return "_$s11Constraints4DeepP5ModelAC_7ElementAA3BooPAegA3FooTn"
        case .inheritedAssociatedType: return "_$s11Constraints7RefinedP5ModelAA6NestedP_7ElementAA3BooPAaHTn"
        }
    }
    var expectedOwner: String {
        switch self {
        case .inheritance: return "Inherited"
        case .composition: return "Composition"
        case .dependent: return "Dependent"
        case .nested: return "Nested"
        case .deep: return "Deep"
        case .inheritedAssociatedType: return "Refined"
        }
    }
    var expectedPath: [String] {
        switch self {
        case .inheritance: return []
        case .composition: return ["Model"]
        case .dependent: return ["Foo"]
        case .nested, .inheritedAssociatedType: return ["Model", "Element"]
        case .deep: return ["Model", "Element", "Element"]
        }
    }
    var expectedQualifiers: [String] {
        switch self {
        case .inheritance: return []
        case .composition: return ["Constraints.Composition"]
        case .dependent: return ["Constraints.Dependent"]
        case .nested, .inheritedAssociatedType: return ["Constraints.Nested", "Constraints.Boo"]
        case .deep: return ["Constraints.Deep", "Constraints.Boo", "Constraints.Boo"]
        }
    }
    var expectedProtocol: String {
        switch self {
        case .dependent, .inheritedAssociatedType: return "Constraints.Boo"
        default: return "Constraints.Foo"
        }
    }
    var expectedMembers: [String] {
        switch self {
        case .inheritance, .inheritedAssociatedType: return []
        default: return [expectedPath[0]]
        }
    }
}

enum MalformedProtocolRequirementFixture: CaseIterable {
    case missingChild, invalidOwner, emptyOwner, invalidTarget, emptyTarget
    case wrongPathKind, emptyPath, wrongComponentKind, emptyComponent, excessChildren, invalidQualifier

    var input: SwiftSymbol {
        get throws {
            var tree = try SwiftSymbol(ProtocolRequirementFixture.nested.input).children[0]
            switch self {
            case .missingChild: tree.children.removeLast()
            case .invalidOwner: tree.children[0] = SwiftSymbol(kind: .identifier, children: tree.children[0].children)
            case .emptyOwner: tree.children[0].children = []
            case .invalidTarget: tree.children[2] = SwiftSymbol(kind: .identifier, children: tree.children[2].children)
            case .emptyTarget: tree.children[2].children = []
            case .wrongPathKind: tree.children[1] = SwiftSymbol(kind: .typeList, children: tree.children[1].children)
            case .emptyPath: tree.children[1].children = []
            case .wrongComponentKind: tree.children[1].children[0] = SwiftSymbol(kind: .identifier, children: tree.children[1].children[0].children)
            case .emptyComponent: tree.children[1].children[0].children = []
            case .excessChildren: tree.children[1].children[0].children.append(SwiftSymbol(kind: .type))
            case .invalidQualifier: tree.children[1].children[0].children[1] = SwiftSymbol(kind: .identifier, children: tree.children[1].children[0].children[1].children)
            }
            return tree
        }
    }
}
