import SwiftDemangle
import SwiftIndexing
import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftBasicFormat

/// Renders every indexed declaration while retaining foreign extension contexts.
struct InterfaceDeclarationRenderer: Sendable {
    let index: SymbolIndexStore
    private var declaredTypeIDs: Set<SymbolDeclaration.ID> = []
    private(set) var diagnostics: [SymbolDiagnostic] = []
    private var genericParameterCountsByDeclarationID: [SymbolDeclaration.ID: Int] = [:]
    private var genericParameterPackIndicesByDeclarationID: [SymbolDeclaration.ID: Set<Int>] = [:]
    private var primaryAssociatedTypesByProtocolID: [SymbolDeclaration.ID: [String]] = [:]
    private var enumCaseRequirementsByTypeID: [SymbolDeclaration.ID: [DemangledNode]] = [:]

    private let reservedNames: Set<String>
    private let requirementsByProtocolID: [SymbolDeclaration.ID: [ProtocolConformanceRequirement]]

    init(index: SymbolIndexStore) {
        self.index = index
        reservedNames = Set(index.declarationsByID.values.map(\.name))
        requirementsByProtocolID = Dictionary(grouping: index.protocolRequirements, by: \.protocolID)
    }

    private enum RenderTask: Sendable {
        case declaration(SymbolDeclaration)
        case typeExtension([SymbolDeclaration])
        case conformance(ProtocolConformance)
    }

    mutating func render() async throws -> [DeclSyntax] {
        collectDeclaredTypes()
        inferGenericCounts()
        for declaration in index.declarationsByID.values where declaration.kind == .enumCase {
            guard let signature = declaration.genericSignature else { continue }
            let owners = nominalAncestors(of: declaration).filter { (genericParameterCountsByDeclarationID[$0] ?? 0) > 0 }
            for requirement in signature.children where requirement.kind != .dependentGenericParamCount {
                guard let depth = genericPositions(in: requirement).map({ $0.0 }).max(), owners.indices.contains(depth) else { continue }
                enumCaseRequirementsByTypeID[owners[depth], default: []].append(requirement)
            }
        }
        var primaryAssociatedTypeCandidates: [SymbolDeclaration.ID: Set<[String]>] = [:]
        for record in index.symbolRecordsByMangledName.values {
            for existential in InterfaceConstrainedExistential.occurrences(in: record.demangledSymbol) {
                let identifier = SymbolDeclaration.ID(structuralKey: existential.protocolType.declarationKey)
                primaryAssociatedTypeCandidates[identifier, default: []].insert(existential.associatedTypeNames)
            }
        }
        primaryAssociatedTypesByProtocolID = primaryAssociatedTypeCandidates.compactMapValues {
            $0.count == 1 ? $0.first : nil
        }
        let roots = index.declarationsByID.values.filter {
            guard case .module = $0.context else { return false }
            return declaredTypeIDs.contains($0.id)
        }.sorted { $0.id.structuralKey < $1.id.structuralKey }
        var tasks = roots.map(RenderTask.declaration)
        var extensionMembersByKey: [String: [SymbolDeclaration]] = [:]
        for declaration in index.declarationsByID.values {
            guard case .typeExtension(let context) = declaration.context else { continue }
            let key = String(context.moduleName.utf8.count) + ":" + context.moduleName + context.extendedType.structuralKey + (context.genericSignature?.declarationKey ?? "")
            extensionMembersByKey[key, default: []].append(declaration)
        }
        for key in extensionMembersByKey.keys.sorted() {
            tasks.append(.typeExtension(extensionMembersByKey[key]!.sorted { $0.id.structuralKey < $1.id.structuralKey }))
        }
        tasks += index.conformances.map(RenderTask.conformance)
        var snapshot = self
        snapshot.diagnostics = []
        let renderer = snapshot
        let results = try await ParallelMap.map(tasks) { task in
            var worker = renderer
            let declaration: DeclSyntax
            switch task {
            case .declaration(let input):
                declaration = try await worker.renderDeclaration(input, types: InterfaceTypeRenderer(), inProtocol: false)
            case .typeExtension(let members): declaration = try await worker.renderExtension(members)
            case .conformance(let input): declaration = worker.renderConformance(input)
            }
            return (declaration, worker.diagnostics)
        }
        var blocks = results.map { $0.0 }
        diagnostics += results.flatMap { $0.1 }
        let unsupportedSymbols = index.symbolRecordsByMangledName.values.filter { $0.role == .unsupported }
            .flatMap { $0.mangledSymbols }
        if !unsupportedSymbols.isEmpty {
            blocks.append(commentDeclaration(["Symbols without a recoverable source declaration"] + Set(unsupportedSymbols).sorted()))
        }
        return blocks
    }
}

fileprivate extension InterfaceDeclarationRenderer {
    mutating func renderExtension(_ members: [SymbolDeclaration]) async throws -> DeclSyntax {
        guard let member = members.first, case .typeExtension(let context) = member.context else {
            preconditionFailure("Expected a nonempty extension group")
        }
        do {
            let types = try contextTypes(for: context.extendedType)
            let requirements = try types.requirements(context.genericSignature)
            let name = try qualifiedName(context.extendedType)
            let body = try await renderDeclarations(members, types: types, inProtocol: false)
            return DeclSyntax(ExtensionDeclSyntax(extendedType: name,
                genericWhereClause: InterfaceTypeRenderer.whereClause(requirements)) {
                self.members(body)
            })
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            for member in members { diagnose(member, "Unresolved extension: \(error)") }
            let name = (try? qualifiedName(context.extendedType).trimmedDescription) ?? "<unknown>"
            return commentDeclaration(["Unresolved extension " + name + ": " + String(describing: error)]
                + members.flatMap(unresolvedDeclaration))
        }
    }

    mutating func renderConformance(_ conformance: ProtocolConformance) -> DeclSyntax {
        do {
            let boundType = conformance.conformingType.interfaceUnderlyingType
            let nominal = boundType.interfaceNominalType
            let identifier = SymbolDeclaration.ID(structuralKey: nominal.declarationKey)
            var types: InterfaceTypeRenderer
            if index.declarationsByID[identifier] != nil {
                types = try contextTypes(for: identifier)
            } else {
                types = InterfaceTypeRenderer()
            }
            for (depth, arguments) in boundType.interfaceGenericArgumentLists.enumerated()
                where types.genericParametersByDepth[depth] == nil {
                _ = try types.addGenericParameters(DemangledNode(kind: .dependentGenericSignature, children: [
                    DemangledNode(kind: .dependentGenericParamCount, contents: .index(UInt64(arguments.count)))
                ]), startingAt: depth, avoiding: [])
            }
            _ = try types.addGenericParameters(conformance.genericSignature, startingAt: 0, avoiding: [])
            let name = try types.type(nominal)
            var requirements = try types.requirements(conformance.genericSignature)
            // A concrete specialization is a same-type condition on an extension.
            if boundType.kind != nominal.kind, boundType.children.count >= 2 {
                let arguments = boundType.interfaceGenericArguments
                let parameters = types.genericParametersByDepth.keys.sorted().flatMap { types.genericParametersByDepth[$0] ?? [] }
                guard arguments.count == parameters.count else {
                    throw InterfaceTypeRenderer.RenderingError("Missing conformance generic context")
                }
                for (parameter, argument) in zip(parameters, arguments) {
                    let underlying = argument.interfaceUnderlyingType
                    if underlying.kind == .pack {
                        guard underlying.children.count == 1,
                              case let expansion = underlying.children[0].interfaceUnderlyingType,
                              expansion.kind == .packExpansion, expansion.children.count == 2,
                              expansion.children[0].declarationKey == expansion.children[1].declarationKey,
                              let (depth, index) = try? expansion.children[0].parameterPosition(),
                              let names = types.genericParametersByDepth[depth], names.indices.contains(index),
                              names[index] == parameter,
                              types.parameterPacks.contains(expansion.children[0].genericParameterPositionKey) else {
                            throw InterfaceTypeRenderer.RenderingError("Unsupported specialized parameter pack conformance")
                        }
                        continue
                    }
                    let value = try types.type(argument)
                    if value.as(IdentifierTypeSyntax.self)?.name.text != parameter {
                        requirements.append(GenericRequirementSyntax(requirement: .sameTypeRequirement(
                            SameTypeRequirementSyntax(leftType: .type(TypeSyntax(IdentifierTypeSyntax(name: .identifier(parameter)))),
                                equal: .binaryOperator("=="), rightType: .type(value)))))
                    }
                }
            }
            return DeclSyntax(try ExtensionDeclSyntax(extendedType: name,
                inheritanceClause: inheritanceClause([types.type(conformance.protocolType)]),
                genericWhereClause: InterfaceTypeRenderer.whereClause(requirements)) {})
        } catch {
            diagnostics.append(SymbolDiagnostic(kind: .incompleteDeclaration,
                message: "Unresolved conformance: \(error)", mangledSymbols: conformance.mangledSymbols, declarationID: nil))
            return commentDeclaration(["Unresolved conformance: \(error)"] + conformance.mangledSymbols.sorted())
        }
    }

    mutating func renderDeclarations(
        _ declarations: [SymbolDeclaration], types: InterfaceTypeRenderer, inProtocol: Bool
    ) async throws -> [DeclSyntax] {
        var snapshot = self
        snapshot.diagnostics = []
        let renderer = snapshot
        let results = try await ParallelMap.map(declarations) { declaration in
            var worker = renderer
            let syntax = try await worker.renderDeclaration(declaration, types: types, inProtocol: inProtocol)
            return (syntax, worker.diagnostics)
        }
        diagnostics += results.flatMap { $0.1 }
        return results.map { $0.0 }
    }

    mutating func collectDeclaredTypes() {
        for declaration in index.declarationsByID.values where declaration.evidence == .direct || declaration.kind == .associatedType {
            var current: SymbolDeclaration? = declaration
            while let ancestor = current {
                declaredTypeIDs.insert(ancestor.id)
                guard case .declaration(let parent) = ancestor.context else { break }
                current = index.declarationsByID[parent]
            }
        }
        declaredTypeIDs.formUnion(requirementsByProtocolID.keys)
    }

    func containsUnresolvedOpaqueReturnType(_ node: DemangledNode, types: InterfaceTypeRenderer) -> Bool {
        if let ordinal = node.opaqueReturnTypeOrdinal {
            guard let recovered = types.opaqueReturnTypes[ordinal] else { return true }
            return recovered.constraints.isEmpty || !recovered.sameTypeRequirements.isEmpty
        }
        return node.children.contains { containsUnresolvedOpaqueReturnType($0, types: types) }
    }

    func commentDeclaration(_ lines: [String]) -> DeclSyntax {
        let trivia = Trivia(pieces: lines.flatMap { line -> [TriviaPiece] in
            [.lineComment("// " + line.replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")), .newlines(1)]
        })
        return DeclSyntax(MissingDeclSyntax(leadingTrivia: trivia, placeholder: .identifier("", presence: .missing)))
    }

    func unresolvedDeclaration(_ declaration: SymbolDeclaration) -> [String] {
        [declaration.name] + declaration.mangledSymbols.sorted()
    }

    func members(_ declarations: [DeclSyntax]) -> MemberBlockItemListSyntax {
        MemberBlockItemListSyntax {
            for declaration in declarations {
                declaration.with(\.leadingTrivia, .newline + declaration.leadingTrivia)
            }
        }
    }

    func inheritanceClause(_ types: [TypeSyntax]) -> InheritanceClauseSyntax? {
        let unique = Dictionary(types.map { ($0.trimmedDescription, $0) }, uniquingKeysWith: { first, _ in first })
        let sorted = unique.keys.sorted().compactMap { unique[$0] }
        guard !sorted.isEmpty else { return nil }
        return InheritanceClauseSyntax {
            for type in sorted {
                InheritedTypeSyntax(type: type)
            }
        }
    }

    mutating func renderDeclaration(
        _ declaration: SymbolDeclaration,
        types inheritedTypes: InterfaceTypeRenderer,
        inProtocol: Bool
    ) async throws -> DeclSyntax {
        try Task.checkCancellation()
        do {
            if hasModifier("override", declaration: declaration), !hasResolvedSuperclassOwner(declaration) {
                throw InterfaceTypeRenderer.RenderingError("Override requires a resolved superclass")
            }
            if let nameNode = declaration.nameNode, [.privateDeclName, .localDeclName].contains(nameNode.kind) {
                diagnose(declaration, "Private or local declaration is emitted with its source name and public visibility; the original discriminator remains in the index.", severity: .warning)
            }
            var types = inheritedTypes
            types.opaqueReturnTypes = Dictionary(uniqueKeysWithValues:
                (index.resolvedFactsBySubject[.declaration(declaration.id)] ?? []).compactMap {
                    guard case .opaqueReturnType(let type) = $0.fact else { return nil }
                    return (type.ordinal, type)
                })
            if let signature = declaration.signature, containsUnresolvedOpaqueReturnType(signature, types: types) {
                diagnose(declaration, "opaque return type is emitted as 'some'; its protocol constraints are unavailable.", severity: .warning)
            }
            if types.opaqueReturnTypes.values.contains(where: { !$0.sameTypeRequirements.isEmpty }) {
                diagnose(declaration, "Opaque same-type requirements are retained in the index; primary associated type syntax is unavailable from the descriptor.", severity: .warning)
            }
            if let signature = declaration.signature,
               !InterfaceConstrainedExistential.occurrences(in: signature).isEmpty {
                diagnose(declaration, "Primary associated type syntax follows encoded constraint order; the protocol's primary associated type declaration and source order are unavailable from mangling.", severity: .warning)
            }
            let isNonFinalClassMember = ownerDeclaration(of: declaration)?.kind == .class
                && (index.resolvedFactsBySubject[.declaration(declaration.id)] ?? []).contains {
                    $0.fact == .modifier(name: "final", isPresent: false)
                }
            let usesClassDispatch = declaration.isStatic && (hasModifier("open", declaration: declaration)
                || hasModifier("override", declaration: declaration) || isNonFinalClassMember)
            let visibility = DeclModifierListSyntax {
                if !inProtocol {
                    DeclModifierSyntax(name: .keyword(hasModifier("open", declaration: declaration) ? .open : .public))
                }
                for (modifier, keyword) in [
                    ("final", Keyword.final), ("override", .override), ("required", .required),
                    ("convenience", .convenience), ("dynamic", .dynamic), ("mutating", .mutating),
                    ("weak", .weak), ("unowned", .unowned),
                ] where hasModifier(modifier, declaration: declaration)
                    && (modifier != "final" || !declaration.isStatic || usesClassDispatch) {
                    DeclModifierSyntax(name: .keyword(keyword))
                }
                if hasModifier("unowned(unsafe)", declaration: declaration) {
                    DeclModifierSyntax(name: .keyword(.unowned), detail: DeclModifierDetailSyntax(detail: .identifier("unsafe")))
                }
                // Swift's module interface printer excludes Lazy and emits accessors.
                if declaration.kind == .enumeration, hasModifier("indirect", declaration: declaration) {
                    DeclModifierSyntax(name: .keyword(.indirect))
                }
            }
            let modifiers = DeclModifierListSyntax {
                visibility
                if declaration.isStatic {
                    DeclModifierSyntax(name: .keyword(usesClassDispatch ? .class : .static))
                }
            }
            switch declaration.kind {
            case .structure, .enumeration, .class, .protocol:
                let isProtocol = declaration.kind == .protocol
                var genericClause: GenericParameterClauseSyntax?
                if isProtocol {
                    types.genericParametersByDepth[0] = ["Self"]
                } else if let count = genericParameterCountsByDeclarationID[declaration.id], count > 0 {
                    genericClause = try types.addGenericParameters(
                        inferredGenericSignature(for: declaration.id, count: count, depth: types.genericParametersByDepth.count),
                        startingAt: types.genericParametersByDepth.count, avoiding: reservedNames)
                    diagnose(declaration, "Generic type parameter names \(genericClause?.formatted().description ?? "") and count are inferred; declaration constraints may be missing.", severity: .info)
                }
                var inheritedDeclarationTypes: [TypeSyntax] = []
                if declaration.kind == .class {
                    for observation in index.resolvedFactsBySubject[.declaration(declaration.id)] ?? [] {
                        if case .superclass(let typeName?) = observation.fact {
                            inheritedDeclarationTypes.append(try types.compilerType(typeName))
                        }
                    }
                }
                var requirements = try types.requirements(enumCaseRequirementsByTypeID[declaration.id].map {
                    DemangledNode(kind: .dependentGenericSignature, children: $0)
                })
                for requirement in requirementsByProtocolID[declaration.id] ?? [] {
                    let protocolType = try types.type(requirement.requiredProtocol)
                    if requirement.associatedTypePath.isEmpty {
                        inheritedDeclarationTypes.append(protocolType)
                    } else {
                        var associatedType = TypeSyntax(IdentifierTypeSyntax(name: .keyword(.Self)))
                        for component in requirement.associatedTypePath {
                            guard let member = try types.type(component).as(IdentifierTypeSyntax.self) else {
                                throw InterfaceTypeRenderer.RenderingError("Invalid associated type path")
                            }
                            associatedType = TypeSyntax(MemberTypeSyntax(baseType: associatedType, name: member.name))
                        }
                        requirements.append(GenericRequirementSyntax(requirement: .conformanceRequirement(
                            ConformanceRequirementSyntax(leftType: associatedType, rightType: protocolType))))
                    }
                }
                let inheritance = inheritanceClause(inheritedDeclarationTypes)
                let name = try InterfaceTypeRenderer.identifier(declaration.name)
                let body = members(try await renderDeclarations(index.members(of: declaration.id).filter {
                    if case .declaration(let parent) = $0.context { return parent == declaration.id }
                    return false
                }, types: types, inProtocol: isProtocol))
                let whereClause = InterfaceTypeRenderer.whereClause(requirements)
                switch declaration.kind {
                case .structure:
                    return DeclSyntax(StructDeclSyntax(modifiers: visibility, name: name, genericParameterClause: genericClause,
                        inheritanceClause: inheritance, genericWhereClause: whereClause) {
                        body
                    })
                case .enumeration:
                    return DeclSyntax(EnumDeclSyntax(modifiers: visibility, name: name, genericParameterClause: genericClause,
                        inheritanceClause: inheritance, genericWhereClause: whereClause) {
                        body
                    })
                case .class:
                    return DeclSyntax(ClassDeclSyntax(modifiers: visibility, name: name, genericParameterClause: genericClause,
                        inheritanceClause: inheritance, genericWhereClause: whereClause) {
                        body
                    })
                default:
                    let primaryAssociatedTypes = try primaryAssociatedTypesByProtocolID[declaration.id].map { names in
                        try PrimaryAssociatedTypeClauseSyntax(primaryAssociatedTypes: PrimaryAssociatedTypeListSyntax {
                            for name in names {
                                PrimaryAssociatedTypeSyntax(name: try InterfaceTypeRenderer.identifier(name))
                            }
                        })
                    }
                    if primaryAssociatedTypes != nil {
                        diagnose(declaration, "Primary associated type list is reconstructed from constrained existential uses.", severity: .info)
                    }
                    return DeclSyntax(ProtocolDeclSyntax(modifiers: visibility, name: name,
                        primaryAssociatedTypeClause: primaryAssociatedTypes,
                        inheritanceClause: inheritance, genericWhereClause: whereClause) {
                        body
                    })
                }
            case .typeAlias:
                throw InterfaceTypeRenderer.RenderingError("Type alias underlying type is unavailable")
            case .associatedType:
                guard inProtocol else { throw InterfaceTypeRenderer.RenderingError("Associated type outside a protocol") }
                return DeclSyntax(try AssociatedTypeDeclSyntax(name: InterfaceTypeRenderer.identifier(declaration.name)))
            case .deinitializer:
                return DeclSyntax(DeinitializerDeclSyntax())
            case .property:
                guard let signature = declaration.signature else { throw InterfaceTypeRenderer.RenderingError("Missing property type") }
                let storage = (index.resolvedFactsBySubject[.declaration(declaration.id)] ?? []).compactMap { observation -> Bool? in
                    if case .storedProperty(let isMutable) = observation.fact { return isMutable }
                    return nil
                }.first
                if ["weak", "unowned", "unowned(unsafe)"].contains(where: { hasModifier($0, declaration: declaration) }), storage == nil {
                    throw InterfaceTypeRenderer.RenderingError("Reference ownership requires resolved property storage")
                }
                let accessorBlock = storage == nil ? accessors(declaration) : nil
                return DeclSyntax(try VariableDeclSyntax(modifiers: modifiers, bindingSpecifier: .keyword(storage == false ? .let : .var)) {
                    try PatternBindingSyntax(pattern: IdentifierPatternSyntax(identifier: InterfaceTypeRenderer.identifier(declaration.name)),
                        typeAnnotation: TypeAnnotationSyntax(type: types.type(signature)), accessorBlock: accessorBlock)
                })
            case .function, .initializer, .subscript, .enumCase:
                guard let signature = declaration.signature else { throw InterfaceTypeRenderer.RenderingError("Missing callable signature") }
                let referencedDepths = genericPositions(in: signature).map { $0.0 }
                let localDepth = max((types.genericParametersByDepth.keys.max().map { $0 + 1 }) ?? 0,
                                     referencedDepths.max() ?? 0)
                if declaration.genericSignature != nil, localDepth > types.genericParametersByDepth.count {
                    diagnose(declaration, "Generic declaration depth \(localDepth) is inferred from encoded parameter references; unreferenced outer parameters are unavailable.", severity: .info)
                }
                let genericClause = try types.addGenericParameters(declaration.genericSignature,
                    startingAt: localDepth, avoiding: reservedNames)
                if let genericClause {
                    diagnose(declaration, "generic parameter names \(genericClause.formatted().description) are inferred; original names are unavailable.", severity: .info)
                }
                let function = try types.function(signature)
                let requirements = try types.requirements(declaration.genericSignature)
                let whereClause = InterfaceTypeRenderer.whereClause(requirements)
                if declaration.kind == .enumCase {
                    let name = try InterfaceTypeRenderer.identifier(declaration.name)
                    var payloadClause: EnumCaseParameterClauseSyntax?
                    if function.result.interfaceUnderlyingType.kind == .functionType {
                        let payload = try types.function(function.result)
                        let parameters = try types.parameters(payload.arguments, labels: declaration.parameterLabels)
                        guard parameters.parameters.allSatisfy({ $0.ellipsis == nil }) else {
                            throw InterfaceTypeRenderer.RenderingError("Unsupported variadic enum payload")
                        }
                        payloadClause = EnumCaseParameterClauseSyntax(parameters: EnumCaseParameterListSyntax {
                            for parameter in parameters.parameters {
                                EnumCaseParameterSyntax(firstName: parameter.firstName, colon: .colonToken(), type: parameter.type)
                            }
                        })
                    }
                    let caseModifiers = DeclModifierListSyntax {
                        if hasModifier("indirect", declaration: declaration), !hasIndirectEnumOwner(declaration) {
                            DeclModifierSyntax(name: .keyword(.indirect))
                        }
                    }
                    return DeclSyntax(EnumCaseDeclSyntax(modifiers: caseModifiers) {
                        EnumCaseElementSyntax(name: name, parameterClause: payloadClause)
                    })
                }
                let parameters = try types.parameters(function.arguments, labels: declaration.parameterLabels)
                if declaration.kind == .initializer {
                    let result = function.result.interfaceUnderlyingType
                    let isOptional = result.kind == .boundGenericEnum
                        && (try? types.type(result.children[0]).trimmedDescription) == "Swift.Optional"
                    return DeclSyntax(InitializerDeclSyntax(attributes: function.attributes, modifiers: visibility,
                        optionalMark: isOptional ? .postfixQuestionMarkToken() : nil, genericParameterClause: genericClause,
                        signature: FunctionSignatureSyntax(parameterClause: parameters, effectSpecifiers: function.effects),
                        genericWhereClause: whereClause))
                }
                if declaration.kind == .subscript {
                    return DeclSyntax(SubscriptDeclSyntax(attributes: function.attributes, modifiers: modifiers,
                        genericParameterClause: genericClause, parameterClause: parameters,
                        returnClause: ReturnClauseSyntax(type: function.resultType), genericWhereClause: whereClause,
                        accessorBlock: accessors(declaration, effects: function.effects)))
                }
                let name: TokenSyntax
                if let nameNode = declaration.nameNode, [.prefixOperator, .postfixOperator, .infixOperator].contains(nameNode.kind) {
                    name = .binaryOperator(declaration.name)
                } else {
                    name = try InterfaceTypeRenderer.identifier(declaration.name)
                }
                let functionModifiers = DeclModifierListSyntax {
                    modifiers
                    if declaration.nameNode?.kind == .prefixOperator { DeclModifierSyntax(name: .keyword(.prefix)) }
                    if declaration.nameNode?.kind == .postfixOperator { DeclModifierSyntax(name: .keyword(.postfix)) }
                }
                return DeclSyntax(FunctionDeclSyntax(attributes: function.attributes, modifiers: functionModifiers, name: name,
                    genericParameterClause: genericClause,
                    signature: FunctionSignatureSyntax(parameterClause: parameters, effectSpecifiers: function.effects,
                        returnClause: ReturnClauseSyntax(type: function.resultType)), genericWhereClause: whereClause))
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            diagnose(declaration, "Unresolved declaration: \(error)")
            return commentDeclaration(["Unresolved declaration: \(error)"] + unresolvedDeclaration(declaration))
        }
    }

    mutating func accessors(_ declaration: SymbolDeclaration, effects: FunctionEffectSpecifiersSyntax? = nil) -> AccessorBlockSyntax {
        let readable = !declaration.accessors.isDisjoint(with: [.getter, .read, .modify, .materializeForSet, .unsafeAddressor])
        if !readable {
            diagnose(declaration, "no readable accessor was exported; 'get' is a reconstruction placeholder. Writability remains unknown unless a writable accessor was observed.", severity: .info)
        }
        let writable = !declaration.accessors.isDisjoint(with: [.setter, .modify, .materializeForSet])
        let hasAddressor = declaration.accessors.contains(.unsafeAddressor)
        let hasMutableAddressor = declaration.accessors.contains(.unsafeMutableAddressor)
        if hasAddressor || hasMutableAddressor {
            diagnose(declaration, "Addressor mutating/nonmutating modifiers are unavailable from exported symbols.", severity: .warning)
        }
        return AccessorBlockSyntax(accessors: .accessors(AccessorDeclListSyntax {
            AccessorDeclSyntax(modifier: hasModifier("lazy", declaration: declaration) && hasValueTypeOwner(declaration) && !declaration.isStatic
                ? DeclModifierSyntax(name: .keyword(.mutating)) : nil,
                accessorSpecifier: .keyword(hasAddressor ? .unsafeAddress : .get),
                effectSpecifiers: effects.map { AccessorEffectSpecifiersSyntax(asyncSpecifier: $0.asyncSpecifier, throwsClause: $0.throwsClause) })
            if hasMutableAddressor {
                AccessorDeclSyntax(accessorSpecifier: .keyword(.unsafeMutableAddress))
            } else if writable { AccessorDeclSyntax(accessorSpecifier: .keyword(.set)) }
        }))
    }

    mutating func diagnose(_ declaration: SymbolDeclaration, _ message: String, severity: SymbolDiagnostic.Severity = .error) {
        diagnostics.append(SymbolDiagnostic(kind: .incompleteDeclaration, message: message,
            mangledSymbols: declaration.mangledSymbols, declarationID: declaration.id, severity: severity))
    }

    func qualifiedName(_ identifier: SymbolDeclaration.ID) throws -> TypeSyntax {
        guard let declaration = index.declarationsByID[identifier] else {
            throw InterfaceTypeRenderer.RenderingError("Missing declaration context")
        }
        let name = try InterfaceTypeRenderer.identifier(declaration.name)
        let baseType: TypeSyntax
        switch declaration.context {
        case .module(let module): baseType = try TypeSyntax(IdentifierTypeSyntax(name: InterfaceTypeRenderer.identifier(module)))
        case .declaration(let parent): baseType = try qualifiedName(parent)
        case .typeExtension(let context): baseType = try qualifiedName(context.extendedType)
        }
        return TypeSyntax(MemberTypeSyntax(baseType: baseType, name: name))
    }

    func contextTypes(for identifier: SymbolDeclaration.ID) throws -> InterfaceTypeRenderer {
        guard let declaration = index.declarationsByID[identifier] else {
            throw InterfaceTypeRenderer.RenderingError("Missing extended type")
        }
        var types: InterfaceTypeRenderer
        switch declaration.context {
        case .module: types = InterfaceTypeRenderer()
        case .declaration(let parent): types = try contextTypes(for: parent)
        case .typeExtension(let context): types = try contextTypes(for: context.extendedType)
        }
        if declaration.kind == .protocol {
            types.genericParametersByDepth[0] = ["Self"]
        } else if let count = genericParameterCountsByDeclarationID[identifier], count > 0 {
            _ = try types.addGenericParameters(
                inferredGenericSignature(for: identifier, count: count, depth: types.genericParametersByDepth.count),
                startingAt: types.genericParametersByDepth.count, avoiding: reservedNames)
        }
        return types
    }

    mutating func inferGenericCounts() {
        for record in index.symbolRecordsByMangledName.values { observeBoundTypes(record.demangledSymbol) }
        let declarations = index.declarationsByID.values.sorted {
            let leftDepth = nominalAncestors(of: $0).count
            let rightDepth = nominalAncestors(of: $1).count
            return leftDepth == rightDepth ? $0.id.structuralKey < $1.id.structuralKey : leftDepth < rightDepth
        }
        for declaration in declarations {
            if case .typeExtension(let context) = declaration.context,
               let extendedType = index.declarationsByID[context.extendedType], case .module = extendedType.context,
               let count = context.genericSignature?.children.first(where: { $0.kind == .dependentGenericParamCount }),
               let value = try? count.smallIndex() {
                genericParameterCountsByDeclarationID[context.extendedType] = max(genericParameterCountsByDeclarationID[context.extendedType] ?? 0, value)
            }
            // A single nominal ancestor makes depth zero unambiguous even when no
            // initializer or other bound reference was exported for that type.
            let parentID: SymbolDeclaration.ID
            switch declaration.context {
            case .declaration(let identifier): parentID = identifier
            case .typeExtension(let context): parentID = context.extendedType
            case .module: continue
            }
            guard let parent = index.declarationsByID[parentID], parent.kind != .protocol,
                  let signature = declaration.signature else { continue }
            let inheritedDepth: Int
            switch parent.context {
            case .module: inheritedDepth = 0
            case .declaration(let ancestor): inheritedDepth = (try? contextTypes(for: ancestor).genericParametersByDepth.count) ?? 0
            case .typeExtension(let context): inheritedDepth = (try? contextTypes(for: context.extendedType).genericParametersByDepth.count) ?? 0
            }
            let positions = genericPositions(in: signature)
            guard declaration.genericSignature == nil || positions.contains(where: { $0.0 > inheritedDepth }) else { continue }
            let count = positions.filter { $0.0 == inheritedDepth }.map { $0.1 + 1 }.max() ?? 0
            genericParameterCountsByDeclarationID[parentID] = max(genericParameterCountsByDeclarationID[parentID] ?? 0, count)
            for position in genericPackPositions(in: signature) where position.0 == inheritedDepth {
                genericParameterPackIndicesByDeclarationID[parentID, default: []].insert(position.1)
            }
        }
    }

    func nominalAncestors(of declaration: SymbolDeclaration) -> [SymbolDeclaration.ID] {
        var ancestors: [SymbolDeclaration.ID] = []
        var context = declaration.context
        while true {
            let identifier: SymbolDeclaration.ID
            switch context {
            case .module: return ancestors.reversed()
            case .declaration(let parent): identifier = parent
            case .typeExtension(let extended): identifier = extended.extendedType
            }
            guard let parent = index.declarationsByID[identifier] else { return ancestors.reversed() }
            ancestors.append(identifier)
            context = parent.context
        }
    }

    func inferredGenericSignature(for identifier: SymbolDeclaration.ID, count: Int, depth: Int) -> DemangledNode {
        let markers = (genericParameterPackIndicesByDeclarationID[identifier] ?? []).sorted().map { index in
            DemangledNode(kind: .dependentGenericParamPackMarker, children: [
                DemangledNode(kind: .dependentGenericParamType, children: [
                    DemangledNode(kind: .index, contents: .index(UInt64(depth))),
                    DemangledNode(kind: .index, contents: .index(UInt64(index)))
                ])
            ])
        }
        return DemangledNode(kind: .dependentGenericSignature, children: [
            DemangledNode(kind: .dependentGenericParamCount, contents: .index(UInt64(count)))
        ] + markers)
    }

    func genericPackPositions(in node: DemangledNode) -> [(Int, Int)] {
        if node.kind == .packExpansion, node.children.count == 2,
           let position = try? node.children[1].interfaceUnderlyingType.parameterPosition() {
            return [position]
        }
        return node.children.flatMap(genericPackPositions)
    }

    func genericPositions(in node: DemangledNode) -> [(Int, Int)] {
        if let position = try? node.parameterPosition() { return [position] }
        return node.children.flatMap(genericPositions)
    }

    mutating func observeBoundTypes(_ node: DemangledNode) {
        if [.boundGenericStructure, .boundGenericClass, .boundGenericEnum].contains(node.kind), node.children.count >= 2 {
            let nominal = node.interfaceNominalType
            let identifier = SymbolDeclaration.ID(structuralKey: nominal.declarationKey)
            genericParameterCountsByDeclarationID[identifier] = max(genericParameterCountsByDeclarationID[identifier] ?? 0, node.children[1].children.count)
            for (position, argument) in node.children[1].children.enumerated() where argument.interfaceUnderlyingType.kind == .pack {
                genericParameterPackIndicesByDeclarationID[identifier, default: []].insert(position)
            }
        }
        for child in node.children { observeBoundTypes(child) }
    }
}

private extension InterfaceDeclarationRenderer {
    func ownerDeclaration(of declaration: SymbolDeclaration) -> SymbolDeclaration? {
        let owner: SymbolDeclaration.ID
        switch declaration.context {
        case .declaration(let identifier): owner = identifier
        case .typeExtension(let context): owner = context.extendedType
        default: return nil
        }
        return index.declarationsByID[owner]
    }

    func hasResolvedSuperclassOwner(_ declaration: SymbolDeclaration) -> Bool {
        guard let owner = ownerDeclaration(of: declaration)?.id else { return false }
        return (index.resolvedFactsBySubject[.declaration(owner)] ?? []).contains {
            if case .superclass(.some) = $0.fact { return true }
            return false
        }
    }

    func hasValueTypeOwner(_ declaration: SymbolDeclaration) -> Bool {
        ownerDeclaration(of: declaration).map { [.structure, .enumeration].contains($0.kind) } == true
    }

    func hasModifier(_ name: String, declaration: SymbolDeclaration) -> Bool {
        (index.resolvedFactsBySubject[.declaration(declaration.id)] ?? []).contains {
            $0.fact == .modifier(name: name, isPresent: true)
        }
    }

    func hasIndirectEnumOwner(_ declaration: SymbolDeclaration) -> Bool {
        guard case .declaration(let owner) = declaration.context, let enumeration = index.declarationsByID[owner] else { return false }
        return hasModifier("indirect", declaration: enumeration)
    }
}

fileprivate extension DemangledNode {
    var interfaceModuleName: String? {
        if kind == .module { return try? nameValue() }
        return children.first?.interfaceModuleName
    }

    var interfaceNominalType: DemangledNode {
        let node = interfaceUnderlyingType
        if node.kind == .extension, (2...3).contains(node.children.count) {
            var context = node
            context.children[1] = node.children[1].interfaceNominalType
            return context
        }
        if [.boundGenericStructure, .boundGenericEnum, .boundGenericClass].contains(node.kind), let base = node.children.first {
            return base.interfaceNominalType
        }
        if node.isTypeDeclaration, node.children.count == 2 {
            return DemangledNode(kind: node.kind, children: [node.children[0].interfaceNominalType, node.children[1]],
                               contents: node.contents)
        }
        return node
    }

    var interfaceGenericArguments: [DemangledNode] {
        let node = interfaceUnderlyingType
        if node.kind == .extension, (2...3).contains(node.children.count) {
            return node.children[1].interfaceGenericArguments
        }
        if [.boundGenericStructure, .boundGenericEnum, .boundGenericClass].contains(node.kind), node.children.count >= 2 {
            return node.children[0].interfaceGenericArguments + node.children[1].children
        }
        if node.isTypeDeclaration, let parent = node.children.first { return parent.interfaceGenericArguments }
        return []
    }

    var interfaceGenericArgumentLists: [[DemangledNode]] {
        let node = interfaceUnderlyingType
        if [.boundGenericStructure, .boundGenericEnum, .boundGenericClass].contains(node.kind), node.children.count >= 2 {
            return node.children[0].interfaceGenericArgumentLists + [node.children[1].children]
        }
        if node.kind == .extension, node.children.count >= 2 { return node.children[1].interfaceGenericArgumentLists }
        if node.isTypeDeclaration, let parent = node.children.first { return parent.interfaceGenericArgumentLists }
        return []
    }
}
