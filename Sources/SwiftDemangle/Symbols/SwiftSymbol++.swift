//
//  SwiftSymbol++.swift
//  SwiftSymbolKit
//
//  Created by Yanan Li on 2026/9/29.
//

extension SwiftSymbol {
    /// Returns the ABI ordinal encoded by an opaque return type node.
    ///
    /// `Qr` denotes ordinal zero; `QR INDEX` denotes `INDEX + 1`.
    package var opaqueReturnTypeOrdinal: Int? {
        guard kind == .opaqueReturnType else { return nil }
        if let child = children.first, case .index(let index) = child.contents,
           let ordinal = Int(exactly: index), ordinal < Int.max {
            return ordinal + 1
        }
        return 0
    }
    
    package var genericParameterPosition: (depth: UInt64, index: UInt64)? {
        guard kind == .dependentGenericParamType, children.count == 2,
              case .index(let depth) = children[0].contents,
              case .index(let index) = children[1].contents else { return nil }
        return (depth, index)
    }
    
    package var isExistentialType: Bool {
        switch self.kind {
            case .existentialMetatype, .protocolList, .protocolListWithClass, .protocolListWithAnyObject: return true
            default: return false
        }
    }
    
    /// The protocol named by an inverse conformance requirement, when its ABI kind is known.
    package var inverseConformanceProtocolName: String? {
        guard kind == .dependentGenericInverseConformanceRequirement,
              children.count == 2, let index = children[1].index,
              let protocolKind = InvertibleProtocolKind(rawValue: index) else { return nil }
        return "Swift.\(protocolKind.sourceName)"
    }
    
    package var isSimpleType: Bool {
        switch kind {
            case .associatedType: fallthrough
            case .associatedTypeRef: fallthrough
            case .boundGenericClass: fallthrough
            case .boundGenericEnum: fallthrough
            case .boundGenericFunction: fallthrough
            case .boundGenericOtherNominalType: fallthrough
            case .boundGenericProtocol: fallthrough
            case .boundGenericStructure: fallthrough
            case .boundGenericTypeAlias: fallthrough
            case .builtinBorrow: fallthrough
            case .builtinTypeName: fallthrough
            case .builtinTupleType: fallthrough
            case .builtinFixedArray: fallthrough
            case .class: fallthrough
            case .dependentGenericType: fallthrough
            case .dependentMemberType: fallthrough
            case .dependentGenericParamType: fallthrough
            case .dynamicSelf: fallthrough
            case .enum: fallthrough
            case .errorType: fallthrough
            case .existentialMetatype: fallthrough
            case .integer: fallthrough
            case .labelList: fallthrough
            case .metatype: fallthrough
            case .metatypeRepresentation: fallthrough
            case .module: fallthrough
            case .negativeInteger: fallthrough
            case .otherNominalType: fallthrough
            case .pack: fallthrough
            case .protocol: fallthrough
            case .protocolSymbolicReference: fallthrough
            case .returnType: fallthrough
            case .silBoxType: fallthrough
            case .silBoxTypeWithLayout: fallthrough
            case .structure: fallthrough
            case .sugaredArray: fallthrough
            case .sugaredDictionary: fallthrough
            case .sugaredInlineArray: fallthrough
            case .sugaredOptional: fallthrough
            case .sugaredParen: fallthrough
            case .tuple: fallthrough
            case .tupleElementName: fallthrough
            case .typeAlias: fallthrough
            case .typeList: fallthrough
            case .typeSymbolicReference: fallthrough
            case .silPackDirect, .silPackIndirect, .constrainedExistentialRequirementList, .constrainedExistentialSelf:
                return true
            case .type:
                return self.children.first.map { $0.isSimpleType } ?? false
            case .protocolList:
                return children.first.map { $0.children.count <= 1 } ?? false
            case .protocolListWithAnyObject:
                return (children.first?.children.first).map { $0.children.count == 0 } ?? false
            default: return false
        }
    }
    
    package var needSpaceBeforeType: Bool {
        switch self.kind {
            case .type: return children.first?.needSpaceBeforeType ?? false
            case .calledOnceFunctionType, .functionType, .noEscapeFunctionType, .uncurriedFunctionType, .dependentGenericType: return false
            default: return true
        }
    }
    
    package func isIdentifier(desired: String) -> Bool {
        return kind == .identifier && text == desired
    }
    
    package var isSwiftModule: Bool {
        return kind == .module && text == stdlibName
    }
}
