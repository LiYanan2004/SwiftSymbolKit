import SwiftDemangle

/// Hand-built trees exercise layouts that exported fixture symbols do not expose.
enum UnsupportedTreeFixture: CaseIterable {
    case unknownWrapper
    case specialization
    case multipleEntities
    case symbolicReference
    case unknownContext
    case associatedTypeWithoutProtocol
    case unmangledSuffix

    var input: SwiftSymbol {
        get throws {
            let function = try parseMangledSwiftSymbol(SymbolExtractionFixture.nestedMethod.input).children[0]
            switch self {
            case .unknownWrapper:
                return SwiftSymbol(kind: .outlinedCopy, children: [function])
            case .specialization:
                return SwiftSymbol(kind: .global, children: [SwiftSymbol(kind: .genericSpecialization), function])
            case .multipleEntities:
                return SwiftSymbol(kind: .global, children: [function, function])
            case .symbolicReference:
                return SwiftSymbol(kind: .typeSymbolicReference, contents: .index(10))
            case .unknownContext:
                var member = function
                member.children[0] = SwiftSymbol(kind: .anonymousContext, children: [function.children[0]])
                return member
            case .associatedTypeWithoutProtocol:
                return SwiftSymbol(kind: .associatedTypeDescriptor, children: [
                    SwiftSymbol(kind: .dependentAssociatedTypeRef, children: [
                        SwiftSymbol(kind: .identifier, contents: .name("Element"))
                    ])
                ])
            case .unmangledSuffix:
                return SwiftSymbol(kind: .global, children: [function, SwiftSymbol(kind: .suffix, contents: .name(".1"))])
            }
        }
    }
}

enum MalformedTreeFixture: CaseIterable {
    case emptyMetadata
    case missingContext
    case missingSignature
    case missingName
    case invalidAccessor
    case invalidExtension

    var input: SwiftSymbol {
        get throws {
            var function = try parseMangledSwiftSymbol(SymbolExtractionFixture.nestedMethod.input).children[0]
            switch self {
            case .emptyMetadata:
                return SwiftSymbol(kind: .typeMetadataAccessFunction)
            case .missingContext:
                return SwiftSymbol(kind: .structure)
            case .missingSignature:
                function.children.removeLast()
                return function
            case .missingName:
                return SwiftSymbol(kind: .structure, children: [SwiftSymbol(kind: .module, contents: .name("Example"))])
            case .invalidAccessor:
                return SwiftSymbol(kind: .getter, children: [function])
            case .invalidExtension:
                function.children[0] = SwiftSymbol(kind: .extension)
                return function
            }
        }
    }
}

enum DeclarationNameFixture: CaseIterable {
    case plain
    case privateName
    case localName
    case infixOperator
    case unicode

    var expectedName: String {
        switch self {
        case .plain: return "hello"
        case .privateName: return "hello"
        case .localName: return "hello"
        case .infixOperator: return "+"
        case .unicode: return "名称"
        }
    }

    var input: SwiftSymbol {
        let identifier = SwiftSymbol(kind: .identifier, contents: .name(expectedName))
        switch self {
        case .privateName:
            return SwiftSymbol(kind: .privateDeclName, children: [
                SwiftSymbol(kind: .identifier, contents: .name("_file")), identifier
            ])
        case .localName:
            return SwiftSymbol(kind: .localDeclName, children: [
                SwiftSymbol(kind: .number, contents: .index(1)), identifier
            ])
        case .infixOperator:
            return SwiftSymbol(kind: .infixOperator, contents: .name(expectedName))
        default:
            return identifier
        }
    }
}
