import SwiftIndexing
import SwiftParser
import SwiftSyntax
import SwiftSyntaxBuilder

/// Syntax for supported demangle nodes, with explicit generic scopes.
struct InterfaceTypeRenderer: Sendable {
    struct RenderingError: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    var genericParametersByDepth: [Int: [String]] = [:]
    var parameterPacks: Set<String> = []
    var opaqueReturnTypes: [Int: OpaqueReturnType] = [:]

    static func identifier(_ name: String) throws -> TokenSyntax {
        if name.isValidSwiftIdentifier(for: .variableName) { return .identifier(name) }
        let escapedName = "`\(name)`"
        guard escapedName.isValidSwiftIdentifier(for: .variableName) else {
            throw RenderingError("Unsupported identifier: \(name)")
        }
        return .identifier(escapedName)
    }

    static func parameterName(depth: Int, index: Int) -> String {
        var remaining = index
        var name = ""
        repeat {
            name = String(UnicodeScalar(65 + remaining % 26)!) + name
            remaining = remaining / 26 - 1
        } while remaining >= 0
        return name + (depth == 0 ? "" : String(depth))
    }

    func type(_ node: DemangledNode) throws -> TypeSyntax {
        switch node.kind {
        case .type, .argumentTuple, .returnType:
            return try type(node.onlyChild())
        case .extension:
            guard (2...3).contains(node.children.count), node.children[0].kind == .module,
                  node.children.count == 2 || node.children[2].kind == .dependentGenericSignature else {
                throw RenderingError("Invalid extension type context")
            }
            // The extension's module and constraints describe its declaration site.
            // A nested type reference is qualified through the extended type itself.
            return try type(node.children[1])
        case .structure, .enum, .class, .protocol, .typeAlias, .otherNominalType:
            guard node.children.count == 2 else { throw RenderingError("Invalid nominal type") }
            return try TypeSyntax(MemberTypeSyntax(baseType: type(node.children[0]),
                name: Self.identifier(node.children[1].nameValue())))
        case .module, .identifier, .tupleElementName:
            return try TypeSyntax(IdentifierTypeSyntax(name: Self.identifier(node.nameValue())))
        case .boundGenericStructure, .boundGenericEnum, .boundGenericClass, .boundGenericTypeAlias:
            guard (2...3).contains(node.children.count), node.children[1].kind == .typeList,
                  node.children.count == 2 || (node.children[2].kind == .typeList && node.children[2].children.allSatisfy { $0.kind == .retroactiveConformance }) else {
                throw RenderingError("Invalid bound generic type")
            }
            let clause = try GenericArgumentClauseSyntax {
                for argument in node.children[1].children {
                    let underlying = argument.interfaceUnderlyingType
                    let elements = underlying.kind == .pack ? underlying.children : [argument]
                    for element in elements {
                        GenericArgumentSyntax(argument: .type(try type(element)))
                    }
                }
            }
            let base = try type(node.children[0])
            if var member = base.as(MemberTypeSyntax.self) {
                member.genericArgumentClause = clause
                return TypeSyntax(member)
            }
            if var identifier = base.as(IdentifierTypeSyntax.self) {
                identifier.genericArgumentClause = clause
                return TypeSyntax(identifier)
            }
            throw RenderingError("Invalid bound generic base type")
        case .dependentGenericParamType:
            let (depth, index) = try node.parameterPosition()
            guard let parameters = genericParametersByDepth[depth], parameters.indices.contains(index) else {
                throw RenderingError("Missing generic parameter at depth \(depth), index \(index)")
            }
            let name = parameters[index]
            let parameter = IdentifierTypeSyntax(name: name == "Self" ? .keyword(.Self) : try Self.identifier(name))
            return parameterPacks.contains(node.genericParameterPositionKey)
                ? TypeSyntax(PackElementTypeSyntax(pack: parameter)) : TypeSyntax(parameter)
        case .dependentMemberType:
            guard node.children.count == 2,
                  let member = try type(node.children[1]).as(IdentifierTypeSyntax.self) else {
                throw RenderingError("Invalid dependent member")
            }
            return try TypeSyntax(MemberTypeSyntax(baseType: type(node.children[0]), name: member.name))
        case .dependentAssociatedTypeRef:
            guard let name = node.children.first else { throw RenderingError("Missing associated type name") }
            return try TypeSyntax(IdentifierTypeSyntax(name: Self.identifier(name.nameValue())))
        case .tuple:
            return try TypeSyntax(TupleTypeSyntax(elements: tupleElements(node)))
        case .functionType, .noEscapeFunctionType, .autoClosureType, .escapingAutoClosureType, .cFunctionPointer, .objCBlock:
            let parts = try function(node)
            let attributes = AttributeListSyntax {
                switch node.kind {
                case .autoClosureType, .escapingAutoClosureType:
                    AttributeSyntax(attributeName: IdentifierTypeSyntax(name: .identifier("autoclosure")))
                case .cFunctionPointer, .objCBlock:
                    AttributeSyntax(attributeName: IdentifierTypeSyntax(name: .identifier("convention")),
                        leftParen: .leftParenToken(), arguments: .argumentList(LabeledExprListSyntax {
                            LabeledExprSyntax(expression: DeclReferenceExprSyntax(
                                baseName: .identifier(node.kind == .cFunctionPointer ? "c" : "block")))
                        }), rightParen: .rightParenToken())
                default: AttributeListSyntax([])
                }
                parts.attributes
            }
            let functionType = FunctionTypeSyntax(parameters: try tupleElements(parts.arguments),
                effectSpecifiers: parts.effects.map { TypeEffectSpecifiersSyntax(asyncSpecifier: $0.asyncSpecifier, throwsClause: $0.throwsClause) },
                returnClause: ReturnClauseSyntax(type: parts.resultType))
            return attributes.isEmpty ? TypeSyntax(functionType)
                : TypeSyntax(AttributedTypeSyntax(specifiers: [], attributes: attributes, baseType: functionType))
        case .inOut: return try specifiedType(.inout, type(node.onlyChild()))
        case .owned: return try specifiedType(.__owned, type(node.onlyChild()))
        case .shared: return try specifiedType(.__shared, type(node.onlyChild()))
        case .sending: return try specifiedType(.sending, type(node.onlyChild()))
        case .isolated: return try specifiedType(.isolated, type(node.onlyChild()))
        case .compileTimeLiteral: return try specifiedType(._const, type(node.onlyChild()))
        case .opaqueReturnType:
            let ordinal: Int
            if let child = node.children.first, case .index(let index) = child.contents,
               let value = Int(exactly: index), value < Int.max { ordinal = value + 1 }
            else { ordinal = 0 }
            if let recovered = opaqueReturnTypes[ordinal], !recovered.constraints.isEmpty,
               recovered.sameTypeRequirements.isEmpty {
                return try TypeSyntax(SomeOrAnyTypeSyntax(someOrAnySpecifier: .keyword(.some),
                    constraint: composition(recovered.constraints.map(type))))
            }
            return TypeSyntax(SomeOrAnyTypeSyntax(someOrAnySpecifier: .keyword(.some),
                constraint: MissingTypeSyntax(placeholder: .identifier("", presence: .missing))))
        case .dynamicSelf: return TypeSyntax(IdentifierTypeSyntax(name: .keyword(.Self)))
        case .constrainedExistential:
            return try TypeSyntax(SomeOrAnyTypeSyntax(someOrAnySpecifier: .keyword(.any),
                constraint: constrainedExistentialProtocol(node)))
        case .metatype, .existentialMetatype:
            let instance = try node.onlyChild()
            if node.kind == .existentialMetatype, instance.interfaceUnderlyingType.kind == .constrainedExistential {
                return try TypeSyntax(SomeOrAnyTypeSyntax(someOrAnySpecifier: .keyword(.any),
                    constraint: MetatypeTypeSyntax(baseType: constrainedExistentialProtocol(instance.interfaceUnderlyingType),
                        metatypeSpecifier: .keyword(.Type))))
            }
            let isExistential = [.protocolList, .protocolListWithClass, .protocolListWithAnyObject]
                .contains(instance.interfaceUnderlyingType.kind)
            return try TypeSyntax(MetatypeTypeSyntax(
                baseType: TupleTypeSyntax(elements: TupleTypeElementListSyntax {
                    TupleTypeElementSyntax(type: try type(instance))
                }),
                metatypeSpecifier: .keyword(node.kind == .metatype && isExistential ? .Protocol : .Type)))
        case .protocolList:
            let list = try node.onlyChild()
            guard list.kind == .typeList else { throw RenderingError("Invalid protocol composition") }
            return try composition(list.children.map(type))
        case .protocolListWithAnyObject:
            let protocols = try type(node.onlyChild())
            let anyObject = TypeSyntax(IdentifierTypeSyntax(name: .identifier("AnyObject")))
            return composition(protocols.as(IdentifierTypeSyntax.self)?.name.tokenKind == .keyword(.Any)
                ? [anyObject] : [protocols, anyObject])
        case .protocolListWithClass:
            guard node.children.count == 2 else { throw RenderingError("Invalid class composition") }
            return try composition(node.children.map(type))
        case .packExpansion:
            guard node.children.count == 2 else { throw RenderingError("Invalid pack expansion") }
            guard parameterPacks.contains(node.children[1].interfaceUnderlyingType.genericParameterPositionKey) else {
                throw RenderingError("Missing generic parameter pack declaration")
            }
            return try TypeSyntax(PackExpansionTypeSyntax(repetitionPattern: type(node.children[0])))
        default:
            throw RenderingError("Unsupported type node: \(node.kind)")
        }
    }

    private func constrainedExistentialProtocol(_ node: DemangledNode) throws -> TypeSyntax {
        guard node.children.count == 2, node.children[1].kind == .constrainedExistentialRequirementList else {
            throw RenderingError("Invalid constrained existential")
        }
        let requirements = node.children[1].children
        if !requirements.isEmpty && requirements.allSatisfy({ $0.kind == .dependentGenericInverseConformanceRequirement }) {
            let base = node.children[0].interfaceUnderlyingType
            guard base.kind == .protocolList, base.children.count == 1, base.children[0].kind == .typeList else {
                throw RenderingError("Invalid inverse-constrained existential")
            }
            let protocols = try base.children[0].children.map(type)
            let suppressedProtocols = try requirements.map { requirement -> TypeSyntax in
                guard requirement.children.first?.interfaceUnderlyingType.kind == .constrainedExistentialSelf else {
                    throw RenderingError("Invalid inverse-constrained existential subject")
                }
                let protocolName = try inverseConformanceProtocolName(requirement)
                return TypeSyntax(stringLiteral: "~\(protocolName)")
            }
            return composition(protocols + suppressedProtocols)
        }
        let existential = try InterfaceConstrainedExistential(node)
        guard var protocolType = try type(existential.protocolType).as(MemberTypeSyntax.self) else {
            throw RenderingError("Invalid constrained existential protocol type")
        }
        protocolType.genericArgumentClause = try GenericArgumentClauseSyntax {
            for argument in existential.arguments {
                GenericArgumentSyntax(argument: .type(try type(argument)))
            }
        }
        return TypeSyntax(protocolType)
    }

    private func inverseConformanceProtocolName(_ requirement: DemangledNode) throws -> String {
        guard requirement.children.count == 2 else { throw RenderingError("Invalid inverse conformance requirement") }
        guard let protocolName = requirement.inverseConformanceProtocolName else {
            throw RenderingError("Unsupported inverse conformance requirement")
        }
        return protocolName
    }

    struct FunctionSignature {
        let arguments: DemangledNode
        let result: DemangledNode
        let resultType: TypeSyntax
        let attributes: AttributeListSyntax
        let effects: FunctionEffectSpecifiersSyntax?
    }

    func function(_ signature: DemangledNode) throws -> FunctionSignature {
        let node = signature.interfaceUnderlyingType
        guard [.functionType, .noEscapeFunctionType, .autoClosureType, .escapingAutoClosureType,
               .cFunctionPointer, .objCBlock].contains(node.kind),
              let arguments = node.children.first(where: { $0.kind == .argumentTuple }),
              let result = node.children.first(where: { $0.kind == .returnType }) else {
            throw RenderingError("Missing function signature")
        }
        let attributes = try AttributeListSyntax {
            for annotation in node.children where annotation.kind != .argumentTuple && annotation.kind != .returnType {
                if let attribute = try functionAttribute(annotation) { attribute }
            }
        }
        let resultType = try node.children.contains { $0.kind == .sendingResultFunctionType }
            ? specifiedType(.sending, type(result)) : type(result)
        let asyncSpecifier: TokenSyntax? = node.children.contains { $0.kind == .asyncAnnotation } ? .keyword(.async) : nil
        let throwsClause = try node.children.first { $0.kind == .throwsAnnotation || $0.kind == .typedThrowsAnnotation }.map {
            $0.kind == .throwsAnnotation ? ThrowsClauseSyntax(throwsSpecifier: .keyword(.throws))
                : try ThrowsClauseSyntax(throwsSpecifier: .keyword(.throws), leftParen: .leftParenToken(),
                    type: type($0.onlyChild()), rightParen: .rightParenToken())
        }
        let effects = asyncSpecifier == nil && throwsClause == nil ? nil
            : FunctionEffectSpecifiersSyntax(asyncSpecifier: asyncSpecifier, throwsClause: throwsClause)
        return FunctionSignature(arguments: try arguments.onlyChild(), result: try result.onlyChild(),
            resultType: resultType, attributes: attributes, effects: effects)
    }

    func parameters(_ arguments: DemangledNode, labels: [String]?) throws -> FunctionParameterClauseSyntax {
        let underlying = arguments.interfaceUnderlyingType
        let elements = underlying.kind == .tuple ? underlying.children : [arguments]
        if let labels, !labels.isEmpty, labels.count != elements.count {
            throw RenderingError("Parameter label count does not match signature")
        }
        return try FunctionParameterClauseSyntax {
            for (position, element) in elements.enumerated() {
                try parameter(element, label: labels.map { $0.isEmpty ? "_" : $0[position] })
            }
        }
    }

    mutating func addGenericParameters(_ signature: DemangledNode?, startingAt depth: Int, avoiding names: Set<String>) throws -> GenericParameterClauseSyntax? {
        guard let signature else { return nil }
        let counts = signature.children.filter { $0.kind == .dependentGenericParamCount }
        var reserved = names.union(genericParametersByDepth.values.flatMap { $0 })
        var introduced: [(depth: Int, index: Int, name: String)] = []
        // Multiple counts describe absolute ABI depths, including empty scopes.
        // A single count can describe a member's local scope after its context.
        for (offset, countNode) in counts.enumerated() {
            let parameterDepth = counts.count == 1 ? depth : offset
            let count = try countNode.smallIndex()
            if let existing = genericParametersByDepth[parameterDepth] {
                guard existing.count == count else {
                    throw RenderingError("Conflicting generic parameter count at depth \(parameterDepth)")
                }
                continue
            }
            let parameters = (0..<count).map { index in
                var name = Self.parameterName(depth: parameterDepth, index: index)
                while reserved.contains(name) { name += "_" }
                reserved.insert(name)
                introduced.append((parameterDepth, index, name))
                return name
            }
            genericParametersByDepth[parameterDepth] = parameters
        }
        for marker in signature.children where marker.kind == .dependentGenericParamPackMarker {
            let parameter = try marker.onlyChild().interfaceUnderlyingType
            parameterPacks.insert(parameter.genericParameterPositionKey)
        }
        guard !introduced.isEmpty else { return nil }
        return GenericParameterClauseSyntax {
            for parameter in introduced {
                let isPack = signature.children.contains { marker in
                    guard marker.kind == .dependentGenericParamPackMarker,
                          let node = marker.children.first?.interfaceUnderlyingType,
                          let position = try? node.parameterPosition() else { return false }
                    return position == (parameter.depth, parameter.index)
                }
                GenericParameterSyntax(specifier: isPack ? .keyword(.each) : nil, name: .identifier(parameter.name))
            }
        }
    }

    func requirements(_ signature: DemangledNode?) throws -> [GenericRequirementSyntax] {
        guard let signature else { return [] }
        return try signature.children.compactMap { requirement -> GenericRequirementSyntax? in
            switch requirement.kind {
            case .dependentGenericParamCount, .dependentGenericParamPackMarker: return nil
            case .dependentGenericConformanceRequirement, .dependentGenericSameTypeRequirement:
                guard requirement.children.count == 2 else { throw RenderingError("Invalid generic requirement") }
                let leftNode = requirement.children[0].interfaceUnderlyingType
                let leftType = parameterPacks.contains(leftNode.genericParameterPositionKey)
                    ? try TypeSyntax(PackExpansionTypeSyntax(repetitionPattern: type(leftNode)))
                    : try type(leftNode)
                let rightType = try type(requirement.children[1])
                return GenericRequirementSyntax(requirement: requirement.kind == .dependentGenericSameTypeRequirement
                    ? .sameTypeRequirement(SameTypeRequirementSyntax(leftType: .type(leftType), equal: .binaryOperator("=="), rightType: .type(rightType)))
                    : .conformanceRequirement(ConformanceRequirementSyntax(leftType: leftType, rightType: rightType)))
            case .dependentGenericLayoutRequirement:
                guard requirement.children.count == 2, try requirement.children[1].nameValue() == "C" else {
                    throw RenderingError("Unsupported generic layout requirement")
                }
                return try GenericRequirementSyntax(requirement: .conformanceRequirement(ConformanceRequirementSyntax(
                    leftType: type(requirement.children[0]), rightType: IdentifierTypeSyntax(name: .identifier("AnyObject")))))
            case .dependentGenericInverseConformanceRequirement:
                let protocolName = try inverseConformanceProtocolName(requirement)
                return try GenericRequirementSyntax(requirement: .conformanceRequirement(ConformanceRequirementSyntax(
                    leftType: type(requirement.children[0]), rightType: TypeSyntax(stringLiteral: "~\(protocolName)"))))
            default: throw RenderingError("Unsupported generic requirement: \(requirement.kind)")
            }
        }
    }

    static func whereClause(_ requirements: [GenericRequirementSyntax]) -> GenericWhereClauseSyntax? {
        let unique = Dictionary(requirements.map { ($0.trimmedDescription, $0) }, uniquingKeysWith: { first, _ in first })
        let sorted = unique.keys.sorted().compactMap { unique[$0] }
        guard !sorted.isEmpty else { return nil }
        return GenericWhereClauseSyntax {
            for requirement in sorted {
                requirement
            }
        }
    }
}

fileprivate extension InterfaceTypeRenderer {
    func functionAttribute(_ annotation: DemangledNode) throws -> AttributeSyntax? {
        switch annotation.kind {
        case .asyncAnnotation, .throwsAnnotation, .typedThrowsAnnotation, .sendingResultFunctionType:
            return nil
        case .concurrentFunctionType:
            return AttributeSyntax(attributeName: IdentifierTypeSyntax(name: .identifier("Sendable")))
        case .globalActorFunctionType:
            return try AttributeSyntax(attributeName: type(annotation.onlyChild()))
        case .isolatedAnyFunctionType:
            return AttributeSyntax(attributeName: IdentifierTypeSyntax(name: .identifier("isolated")),
                leftParen: .leftParenToken(), arguments: .argumentList(LabeledExprListSyntax {
                    LabeledExprSyntax(expression: DeclReferenceExprSyntax(baseName: .identifier("any")))
                }), rightParen: .rightParenToken())
        default: throw RenderingError("Unsupported function annotation: \(annotation.kind)")
        }
    }

    func specifiedType(_ specifier: Keyword, _ baseType: TypeSyntax) -> TypeSyntax {
        TypeSyntax(AttributedTypeSyntax(specifiers: TypeSpecifierListSyntax {
            SimpleTypeSpecifierSyntax(specifier: .keyword(specifier))
        }, baseType: baseType))
    }

    func composition(_ types: [TypeSyntax]) -> TypeSyntax {
        guard !types.isEmpty else { return TypeSyntax(IdentifierTypeSyntax(name: .keyword(.Any))) }
        if types.count == 1 { return types[0] }
        return TypeSyntax(
            CompositionTypeSyntax(elements: CompositionTypeElementListSyntax {
                for (position, type) in types.enumerated() {
                    CompositionTypeElementSyntax(type: type, ampersand: position < types.count - 1 ?  .binaryOperator("&") : nil)
                }
            })
        )
    }

    func tupleElements(_ arguments: DemangledNode) throws -> TupleTypeElementListSyntax {
        let underlying = arguments.interfaceUnderlyingType
        let elements = underlying.kind == .tuple ? underlying.children : [arguments]
        return try TupleTypeElementListSyntax {
            for element in elements {
                try tupleElement(element)
            }
        }
    }

    func tupleElement(_ element: DemangledNode) throws -> TupleTypeElementSyntax {
        if element.kind != .tupleElement { return try TupleTypeElementSyntax(type: type(element)) }
        guard let elementType = element.children.first(where: { $0.kind == .type }) else {
            throw RenderingError("Missing tuple element type")
        }
        guard element.children.allSatisfy({ [.type, .tupleElementName, .variadicMarker].contains($0.kind) }) else {
            throw RenderingError("Unsupported tuple element annotation")
        }
        let label = try element.children.first(where: { $0.kind == .tupleElementName }).map { try Self.identifier($0.nameValue()) }
        return try TupleTypeElementSyntax(firstName: label, colon: label == nil ? nil : .colonToken(), type: type(elementType),
            ellipsis: element.children.contains { $0.kind == .variadicMarker } ? .ellipsisToken() : nil)
    }

    func parameter(_ element: DemangledNode, label: String?) throws -> FunctionParameterSyntax {
        let value = element.kind == .tupleElement ? element.children.first(where: { $0.kind == .type }) : element
        guard let value else { throw RenderingError("Missing parameter type") }
        var parameterType = try type(value)
        let legacyLabel = try element.children.first(where: { $0.kind == .tupleElementName })?.nameValue()
        let name = label ?? legacyLabel ?? "_"
        if [.functionType, .escapingAutoClosureType].contains(value.interfaceUnderlyingType.kind) {
            let attributes = AttributeListSyntax {
                AttributeSyntax(attributeName: IdentifierTypeSyntax(name: .identifier("escaping")))
                if let attributed = parameterType.as(AttributedTypeSyntax.self) { attributed.attributes }
            }
            if var attributed = parameterType.as(AttributedTypeSyntax.self) {
                attributed.attributes = attributes
                parameterType = TypeSyntax(attributed)
            } else {
                parameterType = TypeSyntax(AttributedTypeSyntax(specifiers: [], attributes: attributes, baseType: parameterType))
            }
        }
        return try FunctionParameterSyntax(firstName: name == "_" ? .wildcardToken() : Self.identifier(name), type: parameterType,
            ellipsis: element.children.contains { $0.kind == .variadicMarker } ? .ellipsisToken() : nil)
    }
}

extension DemangledNode {
    var genericParameterPositionKey: String {
        guard let (depth, index) = try? parameterPosition() else { return declarationKey }
        return "\(depth):\(index)"
    }

    var interfaceUnderlyingType: DemangledNode {
        if kind == .type, children.count == 1 { return children[0].interfaceUnderlyingType }
        if kind == .dependentGenericType, children.count == 2 { return children[1].interfaceUnderlyingType }
        return self
    }

    func onlyChild() throws -> DemangledNode {
        guard children.count == 1 else { throw InterfaceTypeRenderer.RenderingError("Invalid \(kind) node") }
        return children[0]
    }

    func nameValue() throws -> String {
        if [.privateDeclName, .localDeclName].contains(kind), children.count == 2 {
            return try children[1].nameValue()
        }
        guard case .name(let name) = contents else { throw InterfaceTypeRenderer.RenderingError("Missing name in \(kind)") }
        return name
    }

    func smallIndex() throws -> Int {
        guard case .index(let index) = contents, index <= 128 else {
            throw InterfaceTypeRenderer.RenderingError("Unsupported index in \(kind)")
        }
        return Int(index)
    }

    func parameterPosition() throws -> (Int, Int) {
        guard kind == .dependentGenericParamType, children.count == 2 else {
            throw InterfaceTypeRenderer.RenderingError("Invalid generic parameter")
        }
        return try (children[0].smallIndex(), children[1].smallIndex())
    }
}
