import SwiftDemangle

/// Extracts declaration facts by following known demangle node layouts.
/// Unrecognized symbols retain their original tree and produce an unsupported diagnostic.
public struct SymbolExtractor {
    public struct Extraction {
        public let record: SymbolRecord
        /// Ancestors precede their members. Referenced signature types are not declarations.
        public let declarations: [SymbolDeclaration]
        public let conformances: [SymbolConformance]
        public let diagnostics: [SymbolDiagnostic]
    }

    public enum ExtractionError: Error {
        /// A supported node has an invalid layout, including manually constructed trees.
        case invalidNode(kind: SwiftSymbol.Kind, reason: String)
    }

    public init() {}

    /// Parses one mangled symbol and extracts its declaration facts.
    /// Throws a demangler error for invalid input or `ExtractionError` for invalid node layouts.
    public func extract(_ mangledSymbol: String) throws -> Extraction {
        try extract(parseMangledSwiftSymbol(mangledSymbol), mangledSymbol: mangledSymbol)
    }

    /// Supply the original spelling for provenance when passing a parsed tree.
    public func extract(_ symbol: SwiftSymbol, mangledSymbol: String) throws -> Extraction {
        var declarations: [SymbolDeclaration] = []
        var conformances: [SymbolConformance] = []
        var role = SymbolRecord.Role.declaration
        do {
            try extractEntity(symbol, mangledSymbol: mangledSymbol, role: &role,
                              declarations: &declarations, conformances: &conformances)
        } catch let unsupported as UnsupportedNode {
            // Discard partial facts so unsupported contexts cannot leave orphan ancestors.
            return Extraction(
                record: SymbolRecord(mangledSymbol: mangledSymbol, demangledSymbol: symbol,
                                     role: .unsupported, declarationIDs: []),
                declarations: [], conformances: [],
                diagnostics: [SymbolDiagnostic(
                    kind: .unsupportedSymbol, message: "Unsupported extraction node: \(unsupported.kind)",
                    mangledSymbols: [mangledSymbol], declarationID: nil
                )]
            )
        }
        return Extraction(
            record: SymbolRecord(mangledSymbol: mangledSymbol, demangledSymbol: symbol, role: role,
                                 declarationIDs: Set(declarations.map(\.id))),
            declarations: declarations, conformances: conformances, diagnostics: []
        )
    }
}

fileprivate extension SymbolExtractor {
    struct UnsupportedNode: Error {
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
        conformances: inout [SymbolConformance]
    ) throws {
        if symbol.kind == .global {
            let entities = symbol.children.filter { !$0.isEntityAttribute }
            guard entities.count == 1 else { throw UnsupportedNode(kind: symbol.kind) }
            for attribute in symbol.children where attribute.isEntityAttribute {
                guard attribute.children.isEmpty else { throw UnsupportedNode(kind: attribute.kind) }
            }
            if entities.count != symbol.children.count { role = .auxiliary }
            try extractEntity(entities[0], mangledSymbol: mangledSymbol, role: &role,
                              declarations: &declarations, conformances: &conformances)
        } else if symbol.kind == .type {
            let declaration = try singleChild(of: symbol)
            guard declaration.isNominalDeclaration else { throw UnsupportedNode(kind: declaration.kind) }
            _ = try appendDeclaration(declaration, evidence: .direct, mangledSymbol: mangledSymbol,
                                      declarations: &declarations)
        } else if let wrapperRole = symbol.extractionRole {
            if role == .declaration { role = wrapperRole }
            try extractEntity(singleChild(of: symbol), mangledSymbol: mangledSymbol, role: &role,
                              declarations: &declarations, conformances: &conformances)
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
        var accessors: Set<SymbolDeclaration.Accessor> = []
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
        guard let declarationKind = entity.declarationKind else { throw UnsupportedNode(kind: entity.kind) }
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
        if !entity.isNominalDeclaration && declarationKind != .deinitializer && signature == nil {
            throw ExtractionError.invalidNode(kind: entity.kind, reason: "Missing declaration signature")
        }
        let labels = try entity.children.first { $0.kind == .labelList }.map { labels in
            try labels.children.map { label in
                if label.kind == .firstElementMarker { return "_" }
                guard label.kind == .identifier else { throw UnsupportedNode(kind: label.kind) }
                return try declarationName(label)
            }
        }
        var identity = entity
        if isEnumCase { identity = SwiftSymbol(kind: .enumCase, children: [identity]) }
        if isStatic { identity = SwiftSymbol(kind: .static, children: [identity]) }
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
                throw UnsupportedNode(kind: genericSignature.kind)
            }
            guard symbol.children[1].isNominalDeclaration else {
                throw UnsupportedNode(kind: symbol.children[1].kind)
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
            guard symbol.children.count == 2 else { throw UnsupportedNode(kind: symbol.kind) }
            return try declarationName(symbol.children[1])
        case .localDeclName:
            guard symbol.children.count == 2 else { throw UnsupportedNode(kind: symbol.kind) }
            return try declarationName(symbol.children[1])
        case .identifier: break
        case .infixOperator: break
        case .prefixOperator: break
        case .postfixOperator: break
        default: throw UnsupportedNode(kind: symbol.kind)
        }
        guard case .name(let name) = symbol.contents else {
            throw ExtractionError.invalidNode(kind: symbol.kind, reason: "Missing identifier text")
        }
        return name
    }

    func appendAssociatedType(
        _ symbol: SwiftSymbol,
        mangledSymbol: String,
        declarations: inout [SymbolDeclaration]
    ) throws {
        let reference = try singleChild(of: symbol)
        guard reference.kind == .dependentAssociatedTypeRef, reference.children.count == 2 else {
            throw UnsupportedNode(kind: reference.kind)
        }
        let protocolType = reference.children[1]
        guard protocolType.kind == .type else { throw UnsupportedNode(kind: protocolType.kind) }
        let protocolDeclaration = try singleChild(of: protocolType)
        guard protocolDeclaration.kind == .protocol else { throw UnsupportedNode(kind: protocolDeclaration.kind) }
        let parent = try appendDeclaration(protocolDeclaration, evidence: .contextOnly,
                                          mangledSymbol: mangledSymbol, declarations: &declarations)
        declarations.append(SymbolDeclaration(
            id: .init(structuralKey: symbol.declarationKey), kind: .associatedType,
            name: try declarationName(reference.children[0]), nameNode: reference.children[0],
            context: .declaration(parent), evidence: .direct, isStatic: false,
            signature: nil, parameterLabels: nil, genericSignature: nil,
            accessors: [], mangledSymbols: [mangledSymbol]
        ))
    }

    func extractConformance(_ symbol: SwiftSymbol, mangledSymbol: String) throws -> SymbolConformance {
        guard symbol.children.count == 3 else { throw UnsupportedNode(kind: symbol.kind) }
        let conformingType = symbol.children[0]
        let protocolType = symbol.children[1]
        let module = symbol.children[2]
        guard conformingType.kind == .type, protocolType.kind == .type,
              module.kind == .module, case .name(let moduleName) = module.contents else {
            throw ExtractionError.invalidNode(kind: symbol.kind, reason: "Invalid protocol conformance layout")
        }
        return SymbolConformance(
            conformingType: conformingType, protocolType: protocolType, moduleName: moduleName,
            genericSignature: conformingType.declarationGenericSignature, mangledSymbols: [mangledSymbol]
        )
    }
}
