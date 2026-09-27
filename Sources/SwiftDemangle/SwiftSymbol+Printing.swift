import Foundation

// MARK: SwiftSymbol extensions for printing

extension SwiftSymbol.Kind {
	var isExistentialType: Bool {
		switch self {
		case .existentialMetatype, .protocolList, .protocolListWithClass, .protocolListWithAnyObject: return true
		default: return false
		}
	}
}

extension SwiftSymbol {
	var isSimpleType: Bool {
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
	
	var needSpaceBeforeType: Bool {
		switch self.kind {
		case .type: return children.first?.needSpaceBeforeType ?? false
		case .calledOnceFunctionType, .functionType, .noEscapeFunctionType, .uncurriedFunctionType, .dependentGenericType: return false
		default: return true
		}
	}
	
	func isIdentifier(desired: String) -> Bool {
		return kind == .identifier && text == desired
	}
	
	var isSwiftModule: Bool {
		return kind == .module && text == stdlibName
	}
}

enum SugarType {
	case none
	case optional
	case implicitlyUnwrappedOptional
	case array
	case dictionary
}

enum TypePrinting {
	case noType
	case withColon
	case functionStyle
}
