import SwiftDemangle

/// Extracts declaration facts by following known demangle node layouts.
/// Unrecognized symbols retain their original tree and produce an unsupported diagnostic.
public struct SymbolExtractor {
    public struct ExtractionResult {
        public let record: SymbolRecord
        /// Ancestors precede their members. Referenced signature types are not declarations.
        public let declarations: [SymbolDeclaration]
        public let conformances: [ProtocolConformance]
        public let protocolRequirements: [ProtocolConformanceRequirement]
        public let runtimeSymbols: [RuntimeSymbolRecord]
        public let diagnostics: [SymbolDiagnostic]
    }

    public enum ExtractionError: Error {
        /// A supported node has an invalid layout, including manually constructed trees.
        case invalidNode(kind: SwiftSymbol.Kind, reason: String)
    }

    public init() {}

    /// Parses one mangled symbol and extracts its declaration facts.
    /// Throws a demangler error for invalid input or `ExtractionError` for invalid node layouts.
    public func extract(_ mangledSymbol: String) throws -> ExtractionResult {
        try extract(SwiftSymbol(mangledSymbol), mangledSymbol: mangledSymbol)
    }

    /// Supply the original spelling for provenance when passing a parsed tree.
    public func extract(_ symbol: SwiftSymbol, mangledSymbol: String) throws -> ExtractionResult {
        var declarations: [SymbolDeclaration] = []
        var conformances: [ProtocolConformance] = []
        var protocolRequirements: [ProtocolConformanceRequirement] = []
        var runtimeSymbols: [RuntimeSymbolRecord] = []
        var role = SymbolRecord.Role.declaration
        do {
            try extractEntity(symbol, mangledSymbol: mangledSymbol, role: &role,
                              declarations: &declarations, conformances: &conformances,
                              protocolRequirements: &protocolRequirements, runtimeSymbols: &runtimeSymbols)
        } catch let unsupported as UnsupportedNodeError {
            // Discard partial facts so unsupported contexts cannot leave orphan ancestors.
            return ExtractionResult(
                record: SymbolRecord(mangledSymbol: mangledSymbol, demangledSymbol: symbol,
                                     role: .unsupported, declarationIDs: []),
                declarations: [], conformances: [], protocolRequirements: [], runtimeSymbols: [],
                diagnostics: [SymbolDiagnostic(
                    kind: .unsupportedSymbol, message: "Unsupported extraction node: \(unsupported.kind)",
                    mangledSymbols: [mangledSymbol], declarationID: nil
                )]
            )
        }
        return ExtractionResult(
            record: SymbolRecord(mangledSymbol: mangledSymbol, demangledSymbol: symbol, role: role,
                                 declarationIDs: Set(declarations.map(\.id))),
            declarations: declarations, conformances: conformances,
            protocolRequirements: protocolRequirements, runtimeSymbols: runtimeSymbols, diagnostics: []
        )
    }
}

fileprivate extension SymbolExtractor {
    struct UnsupportedNodeError: Error {
        let kind: SwiftSymbol.Kind
    }

    func singleChild(of symbol: SwiftSymbol) throws -> SwiftSymbol {
        guard symbol.children.count == 1 else {
            throw ExtractionError.invalidNode(kind: symbol.kind, reason: "Expected exactly one child")
        }
        return symbol.children[0]
    }

    func extractEntity(
        _ symbol: SwiftSymbol,
        mangledSymbol: String,
        role: inout SymbolRecord.Role,
        declarations: inout [SymbolDeclaration],
        conformances: inout [ProtocolConformance],
        protocolRequirements: inout [ProtocolConformanceRequirement],
        runtimeSymbols: inout [RuntimeSymbolRecord]
    ) throws {
        if symbol.kind == .global {
            let entities = symbol.children.filter { !$0.isEntityAttribute }
            guard entities.count == 1 else { throw UnsupportedNodeError(kind: symbol.kind) }
            for attribute in symbol.children where attribute.isEntityAttribute {
                guard attribute.children.isEmpty else { throw UnsupportedNodeError(kind: attribute.kind) }
            }
            if let attribute = symbol.children.first(where: \.isEntityAttribute) {
                role = .auxiliary(attribute.kind)
            }
            try extractEntity(entities[0], mangledSymbol: mangledSymbol, role: &role,
                              declarations: &declarations, conformances: &conformances,
                              protocolRequirements: &protocolRequirements, runtimeSymbols: &runtimeSymbols)
        } else if [.protocolWitness, .fieldOffset, .initializer, .propertyWrapperBackingInitializer,
                   .objCResilientClassStub, .fullObjCResilientClassStub].contains(symbol.kind) {
            let expectedChildCount = symbol.kind == .protocolWitness || symbol.kind == .fieldOffset ? 2 : 1
            guard symbol.children.count == expectedChildCount else {
                throw ExtractionError.invalidNode(kind: symbol.kind, reason: "Expected \(expectedChildCount) children")
            }
            // Retain compiler support entries without synthesizing source declarations.
            if role == .declaration { role = .auxiliary(symbol.kind) }
        } else if symbol.kind == .defaultArgumentInitializer {
            guard symbol.children.count == 2, symbol.children[1].kind == .number,
                  case .index = symbol.children[1].contents else {
                throw ExtractionError.invalidNode(kind: symbol.kind, reason: "Expected a declaration and default argument index")
            }
            // Compiler-generated entry point, retained in the symbol record only.
            // Its expression and source-level default value cannot be recovered here.
            role = .auxiliary(.defaultArgumentInitializer)
        } else if symbol.kind == .type {
            let declaration = try singleChild(of: symbol)
            guard declaration.isTypeDeclaration else { throw UnsupportedNodeError(kind: declaration.kind) }
            _ = try appendDeclaration(declaration, evidence: .direct, mangledSymbol: mangledSymbol,
                                      declarations: &declarations)
        } else if let wrapperRole = symbol.extractionRole {
            if role == .declaration { role = wrapperRole }
            try extractEntity(singleChild(of: symbol), mangledSymbol: mangledSymbol, role: &role,
                              declarations: &declarations, conformances: &conformances,
                              protocolRequirements: &protocolRequirements, runtimeSymbols: &runtimeSymbols)
        } else if symbol.kind == .classMetadataBaseOffset || symbol.kind == .methodLookupFunction {
            if role == .declaration { role = .auxiliary(symbol.kind) }
            let type = try singleChild(of: symbol)
            guard type.kind == .type else {
                throw ExtractionError.invalidNode(kind: symbol.kind, reason: "Expected a class type")
            }
            let declaration = try singleChild(of: type)
            guard declaration.kind == .class else { throw UnsupportedNodeError(kind: declaration.kind) }
            let declarationID = try appendDeclaration(declaration, evidence: .contextOnly,
                                                      mangledSymbol: mangledSymbol, declarations: &declarations)
            runtimeSymbols.append(RuntimeSymbolRecord(
                kind: symbol.kind == .classMetadataBaseOffset ? .classMetadataBaseOffset : .methodLookupFunction,
                declarationID: declarationID, mangledSymbols: [mangledSymbol]
            ))
        } else if symbol.kind == .baseConformanceDescriptor || symbol.kind == .associatedConformanceDescriptor {
            if role == .declaration { role = .descriptor }
            try appendProtocolRequirement(symbol, mangledSymbol: mangledSymbol,
                                          declarations: &declarations, requirements: &protocolRequirements)
        } else if symbol.kind == .protocolConformance {
            conformances.append(try extractConformance(symbol, mangledSymbol: mangledSymbol))
        } else if symbol.kind == .associatedTypeDescriptor {
            if role == .declaration { role = .descriptor }
            try appendAssociatedType(symbol, mangledSymbol: mangledSymbol, declarations: &declarations)
        } else {
            _ = try appendDeclaration(symbol, evidence: .direct, mangledSymbol: mangledSymbol,
                                      declarations: &declarations)
            if let declaration = declarations.last, !declaration.accessors.isEmpty, role == .declaration {
                role = .accessor
            }
        }
    }

    @discardableResult
    func appendDeclaration(
        _ symbol: SwiftSymbol,
        evidence: SymbolDeclaration.Evidence,
        mangledSymbol: String,
        declarations: inout [SymbolDeclaration]
    ) throws -> SymbolDeclaration.ID {
        var entity = symbol
        var isStatic = false
        var accessors: Set<SymbolDeclaration.AccessorKind> = []
        var isEnumCase = false
        while entity.kind == .static || entity.accessorKind != nil || entity.kind == .enumCase {
            if entity.kind == .static {
                isStatic = true
            } else if let accessor = entity.accessorKind {
                accessors.insert(accessor)
            } else {
                isEnumCase = true
            }
            entity = try singleChild(of: entity)
        }
        guard let declarationKind = entity.declarationKind else { throw UnsupportedNodeError(kind: entity.kind) }
        guard let parent = entity.children.first else {
            throw ExtractionError.invalidNode(kind: entity.kind, reason: "Missing declaration context")
        }
        if !accessors.isEmpty && declarationKind != .property && declarationKind != .subscript {
            throw ExtractionError.invalidNode(kind: entity.kind, reason: "Accessor requires a storage declaration")
        }
        if isEnumCase && (entity.kind != .function || parent.kind != .enum) {
            throw ExtractionError.invalidNode(kind: entity.kind, reason: "Enum case requires an enum constructor function")
        }
        let context = try extractContext(parent, mangledSymbol: mangledSymbol, declarations: &declarations)
        let name: String
        let nameNode: SwiftSymbol?
        switch declarationKind {
        case .initializer:
            name = "init"
            nameNode = nil
        case .deinitializer:
            name = "deinit"
            nameNode = nil
        case .subscript:
            name = "subscript"
            nameNode = nil
        default:
            guard entity.children.count > 1 else {
                throw ExtractionError.invalidNode(kind: entity.kind, reason: "Missing declaration name")
            }
            nameNode = entity.children[1]
            name = try declarationName(entity.children[1])
        }
        let signature = entity.children.dropFirst().first { $0.kind == .type }
        if !entity.isTypeDeclaration && declarationKind != .deinitializer && signature == nil {
            throw ExtractionError.invalidNode(kind: entity.kind, reason: "Missing declaration signature")
        }
        let labels = try entity.children.first { $0.kind == .labelList }.map { labels in
            try labels.children.map { label in
                if label.kind == .firstElementMarker { return "_" }
                guard label.kind == .identifier else { throw UnsupportedNodeError(kind: label.kind) }
                return try declarationName(label)
            }
        }
        var identity = entity

        if isEnumCase {
            identity = SwiftSymbol(kind: .enumCase, children: [identity])
        } else if isStatic {
            identity = SwiftSymbol(kind: .static, children: [identity])
        }

        let identifier = SymbolDeclaration.ID(structuralKey: identity.declarationKey)
        declarations.append(SymbolDeclaration(
            id: identifier, kind: isEnumCase ? .enumCase : declarationKind, name: name, nameNode: nameNode,
            context: context, evidence: evidence, isStatic: isStatic, signature: signature,
            parameterLabels: labels, genericSignature: signature?.declarationGenericSignature,
            accessors: accessors, mangledSymbols: [mangledSymbol]
        ))

        return identifier
    }

    func extractContext(
        _ symbol: SwiftSymbol,
        mangledSymbol: String,
        declarations: inout [SymbolDeclaration]
    ) throws -> DeclarationContext {
        if symbol.kind == .module {
            guard case .name(let moduleName) = symbol.contents else {
                throw ExtractionError.invalidNode(kind: symbol.kind, reason: "Missing module name")
            }
            return .module(moduleName)
        }
        if symbol.kind == .extension {
            guard (2...3).contains(symbol.children.count), symbol.children[0].kind == .module,
                  case .name(let moduleName) = symbol.children[0].contents else {
                throw ExtractionError.invalidNode(kind: symbol.kind, reason: "Invalid extension context")
            }
            let genericSignature = symbol.children.count == 3 ? symbol.children[2] : nil
            if let genericSignature, genericSignature.kind != .dependentGenericSignature {
                throw UnsupportedNodeError(kind: genericSignature.kind)
            }
            guard symbol.children[1].isTypeDeclaration else {
                throw UnsupportedNodeError(kind: symbol.children[1].kind)
            }
            let extendedType = try appendDeclaration(symbol.children[1], evidence: .contextOnly,
                                                      mangledSymbol: mangledSymbol, declarations: &declarations)
            return .typeExtension(.init(moduleName: moduleName, extendedType: extendedType,
                                        genericSignature: genericSignature))
        }
        return .declaration(try appendDeclaration(symbol, evidence: .contextOnly,
                                                   mangledSymbol: mangledSymbol, declarations: &declarations))
    }

    func declarationName(_ symbol: SwiftSymbol) throws -> String {
        switch symbol.kind {
        case .privateDeclName:
            guard symbol.children.count == 2 else { throw UnsupportedNodeError(kind: symbol.kind) }
            return try declarationName(symbol.children[1])
        case .localDeclName:
            guard symbol.children.count == 2 else { throw UnsupportedNodeError(kind: symbol.kind) }
            return try declarationName(symbol.children[1])
        case .identifier: break
        case .infixOperator: break
        case .prefixOperator: break
        case .postfixOperator: break
        default: throw UnsupportedNodeError(kind: symbol.kind)
        }
        guard case .name(let name) = symbol.contents else {
            throw ExtractionError.invalidNode(kind: symbol.kind, reason: "Missing identifier text")
        }
        return name
    }

    func appendAssociatedType(
        _ symbol: SwiftSymbol,
        evidence: SymbolDeclaration.Evidence = .direct,
        mangledSymbol: String,
        declarations: inout [SymbolDeclaration]
    ) throws {
        let reference = try singleChild(of: symbol)
        guard reference.kind == .dependentAssociatedTypeRef, reference.children.count == 2 else {
            throw UnsupportedNodeError(kind: reference.kind)
        }
        let protocolType = reference.children[1]
        guard protocolType.kind == .type else { throw UnsupportedNodeError(kind: protocolType.kind) }
        let protocolDeclaration = try singleChild(of: protocolType)
        guard protocolDeclaration.kind == .protocol else { throw UnsupportedNodeError(kind: protocolDeclaration.kind) }
        let parent = try appendDeclaration(protocolDeclaration, evidence: .contextOnly,
                                          mangledSymbol: mangledSymbol, declarations: &declarations)
        declarations.append(SymbolDeclaration(
            id: .init(structuralKey: symbol.declarationKey), kind: .associatedType,
            name: try declarationName(reference.children[0]), nameNode: reference.children[0],
            context: .declaration(parent), evidence: evidence, isStatic: false,
            signature: nil, parameterLabels: nil, genericSignature: nil,
            accessors: [], mangledSymbols: [mangledSymbol]
        ))
    }

    func appendProtocolRequirement(
        _ symbol: SwiftSymbol,
        mangledSymbol: String,
        declarations: inout [SymbolDeclaration],
        requirements: inout [ProtocolConformanceRequirement]
    ) throws {
        let isAssociatedType = symbol.kind == .associatedConformanceDescriptor
        guard symbol.children.count == (isAssociatedType ? 3 : 2) else {
            throw ExtractionError.invalidNode(kind: symbol.kind, reason: "Invalid protocol requirement layout")
        }
        let protocolType = symbol.children[0]
        let requiredProtocol = symbol.children[isAssociatedType ? 2 : 1]
        guard protocolType.kind == .type, requiredProtocol.kind == .type else {
            throw ExtractionError.invalidNode(kind: symbol.kind, reason: "Expected protocol type nodes")
        }
        let protocolDeclaration = try singleChild(of: protocolType)
        let requiredDeclaration = try singleChild(of: requiredProtocol)
        guard protocolDeclaration.kind == .protocol else { throw UnsupportedNodeError(kind: protocolDeclaration.kind) }
        guard requiredDeclaration.kind == .protocol else { throw UnsupportedNodeError(kind: requiredDeclaration.kind) }

        var path: [SwiftSymbol] = []
        if isAssociatedType {
            let associatedTypePath = symbol.children[1]
            guard associatedTypePath.kind == .assocTypePath, !associatedTypePath.children.isEmpty else {
                throw ExtractionError.invalidNode(kind: symbol.kind, reason: "Expected a nonempty associated-type path")
            }
            path = associatedTypePath.children
            for component in path {
                guard component.kind == .dependentAssociatedTypeRef,
                      (1...2).contains(component.children.count) else {
                    throw ExtractionError.invalidNode(kind: component.kind, reason: "Invalid associated-type path component")
                }
                _ = try declarationName(component.children[0])
                if component.children.count == 2 {
                    let qualifier = component.children[1]
                    guard qualifier.kind == .type else {
                        throw ExtractionError.invalidNode(kind: component.kind, reason: "Expected a protocol qualifier")
                    }
                    let qualifierDeclaration = try singleChild(of: qualifier)
                    guard qualifierDeclaration.kind == .protocol else { throw UnsupportedNodeError(kind: qualifierDeclaration.kind) }
                }
            }
        }
        let protocolID = SymbolDeclaration.ID(structuralKey: protocolDeclaration.declarationKey)
        // Only infer a member when its qualifier identifies this protocol. Subsequent
        // components and inherited associated types remain qualified references.
        if let root = path.first, root.children.count == 2,
           root.children[1].declarationKey == protocolType.declarationKey {
            try appendAssociatedType(SwiftSymbol(kind: .associatedTypeDescriptor, children: [root]),
                                     evidence: .contextOnly, mangledSymbol: mangledSymbol,
                                     declarations: &declarations)
        } else {
            try appendDeclaration(protocolDeclaration, evidence: .contextOnly,
                                  mangledSymbol: mangledSymbol, declarations: &declarations)
        }
        requirements.append(ProtocolConformanceRequirement(
            protocolID: protocolID, associatedTypePath: path,
            requiredProtocol: requiredProtocol, mangledSymbols: [mangledSymbol]
        ))
    }

    func extractConformance(_ symbol: SwiftSymbol, mangledSymbol: String) throws -> ProtocolConformance {
        guard symbol.children.count == 3 else { throw UnsupportedNodeError(kind: symbol.kind) }
        let conformingType = symbol.children[0]
        let protocolType = symbol.children[1]
        let module = symbol.children[2]
        guard conformingType.kind == .type, protocolType.kind == .type,
              module.kind == .module, case .name(let moduleName) = module.contents else {
            throw ExtractionError.invalidNode(kind: symbol.kind, reason: "Invalid protocol conformance layout")
        }
        return ProtocolConformance(
            conformingType: conformingType, protocolType: protocolType, moduleName: moduleName,
            genericSignature: conformingType.declarationGenericSignature, mangledSymbols: [mangledSymbol]
        )
    }
}
