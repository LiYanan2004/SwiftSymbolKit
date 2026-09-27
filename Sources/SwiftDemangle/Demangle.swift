import Foundation

// MARK: Demangle.h

/// These options mimic those used in the Swift project. Check that project for details.
public struct SymbolPrintOptions: OptionSet, Sendable {
	public let rawValue: Int
	
	public static let synthesizeSugarOnTypes = SymbolPrintOptions(rawValue: 1 << 0)
	public static let displayDebuggerGeneratedModule = SymbolPrintOptions(rawValue: 1 << 1)
	public static let qualifyEntities = SymbolPrintOptions(rawValue: 1 << 2)
	public static let displayExtensionContexts = SymbolPrintOptions(rawValue: 1 << 3)
	public static let displayUnmangledSuffix = SymbolPrintOptions(rawValue: 1 << 4)
	public static let displayModuleNames = SymbolPrintOptions(rawValue: 1 << 5)
	public static let displayGenericSpecializations = SymbolPrintOptions(rawValue: 1 << 6)
	public static let displayProtocolConformances = SymbolPrintOptions(rawValue: 1 << 7)
	public static let displayWhereClauses = SymbolPrintOptions(rawValue: 1 << 8)
	public static let displayEntityTypes = SymbolPrintOptions(rawValue: 1 << 9)
	public static let shortenPartialApply = SymbolPrintOptions(rawValue: 1 << 10)
	public static let shortenThunk = SymbolPrintOptions(rawValue: 1 << 11)
	public static let shortenValueWitness = SymbolPrintOptions(rawValue: 1 << 12)
	public static let shortenArchetype = SymbolPrintOptions(rawValue: 1 << 13)
	public static let showPrivateDiscriminators = SymbolPrintOptions(rawValue: 1 << 14)
	public static let showFunctionArgumentTypes = SymbolPrintOptions(rawValue: 1 << 15)
	public static let showAsyncResumePartial = SymbolPrintOptions(rawValue: 1 << 16)
	public static let displayStdlibModule = SymbolPrintOptions(rawValue: 1 << 17)
	public static let displayObjCModule = SymbolPrintOptions(rawValue: 1 << 18)
	public static let printForTypeName = SymbolPrintOptions(rawValue: 1 << 19)
	public static let showClosureSignature = SymbolPrintOptions(rawValue: 1 << 20)
	public static let classify = SymbolPrintOptions(rawValue: 1 << 21)
	
	public init(rawValue: Int) {
		self.rawValue = rawValue
	}
	
	public static let `default`: SymbolPrintOptions = [.displayDebuggerGeneratedModule, .qualifyEntities, .displayExtensionContexts, .displayUnmangledSuffix, .displayModuleNames, .displayGenericSpecializations, .displayProtocolConformances, .displayWhereClauses, .displayEntityTypes, .showPrivateDiscriminators, .showFunctionArgumentTypes, .showAsyncResumePartial, .displayStdlibModule, .displayObjCModule, .showClosureSignature]
	public static let simplified: SymbolPrintOptions = [.synthesizeSugarOnTypes, .qualifyEntities, .shortenPartialApply, .shortenThunk, .shortenValueWitness, .shortenArchetype]
}

enum FunctionSigSpecializationParamKind: UInt64 {
	case constantPropFunction = 0
	case constantPropGlobal = 1
	case constantPropInteger = 2
	case constantPropFloat = 3
	case constantPropString = 4
	case closureProp = 5
	case boxToValue = 6
	case boxToStack = 7
	case inOutToOut = 8
	case constantPropKeyPath = 9
	case constantPropStruct = 10
	case closurePropPreviousArg = 11
	case escapingClosureProp = 12
	
	case dead = 64
	case ownedToGuaranteed = 128
	case sroa = 256
	case guaranteedToOwned = 512
	case existentialToGeneric = 1024
}

enum SpecializationPass {
	case allocBoxToStack
	case closureSpecializer
	case capturePromotion
	case capturePropagation
	case functionSignatureOpts
	case genericSpecializer
}

enum Differentiability: UnicodeScalar {
	case normal = "d"
	case linear = "l"
	case forward = "f"
	case reverse = "r"
	
	init?(_ uint64: UInt64) {
		guard let uint32 = UInt32(exactly: uint64), let scalar = UnicodeScalar(uint32), let value = Differentiability(rawValue: scalar) else { return nil }
		self = value
	}
}

enum AutoDiffFunctionKind: UnicodeScalar {
	case forward = "f"
	case reverse = "r"
	case differential = "d"
	case pullback = "p"
	
	init?(_ uint64: UInt64) {
		guard let uint32 = UInt32(exactly: uint64), let scalar = UnicodeScalar(uint32), let value = AutoDiffFunctionKind(rawValue: scalar) else { return nil }
		self = value
	}
}

enum Directness: UInt64, CustomStringConvertible {
	case direct = 0
	case indirect = 1
	
	var description: String {
		switch self {
		case .direct: return "direct"
		case .indirect: return "indirect"
		}
	}
}

enum DemangleFunctionEntityArgs {
	case none, typeAndMaybePrivateName, typeAndIndex, index
}

enum DemangleGenericRequirementTypeKind {
	case generic, assoc, compoundAssoc, substitution
}

enum DemangleGenericRequirementConstraintKind {
	case `protocol`
	case baseClass
	case sameType
	case sameShape
	case layout
	case packMarker
	case inverse
	case valueMarker
}

enum ValueWitnessKind: UInt64, CustomStringConvertible {
	case allocateBuffer = 0
	case assignWithCopy = 1
	case assignWithTake = 2
	case deallocateBuffer = 3
	case destroy = 4
	case destroyArray = 5
	case destroyBuffer = 6
	case initializeBufferWithCopyOfBuffer = 7
	case initializeBufferWithCopy = 8
	case initializeWithCopy = 9
	case initializeBufferWithTake = 10
	case initializeWithTake = 11
	case projectBuffer = 12
	case initializeBufferWithTakeOfBuffer = 13
	case initializeArrayWithCopy = 14
	case initializeArrayWithTakeFrontToBack = 15
	case initializeArrayWithTakeBackToFront = 16
	case storeExtraInhabitant = 17
	case getExtraInhabitantIndex = 18
	case getEnumTag = 19
	case destructiveProjectEnumData = 20
	case destructiveInjectEnumTag = 21
	case getEnumTagSinglePayload = 22
	case storeEnumTagSinglePayload = 23
	
	init?(code: String) {
		switch code {
		case "al": self = .allocateBuffer
		case "ca": self = .assignWithCopy
		case "ta": self = .assignWithTake
		case "de": self = .deallocateBuffer
		case "xx": self = .destroy
		case "XX": self = .destroyBuffer
		case "Xx": self = .destroyArray
		case "CP": self = .initializeBufferWithCopyOfBuffer
		case "Cp": self = .initializeBufferWithCopy
		case "cp": self = .initializeWithCopy
		case "Tk": self = .initializeBufferWithTake
		case "tk": self = .initializeWithTake
		case "pr": self = .projectBuffer
		case "TK": self = .initializeBufferWithTakeOfBuffer
		case "Cc": self = .initializeArrayWithCopy
		case "Tt": self = .initializeArrayWithTakeFrontToBack
		case "tT": self = .initializeArrayWithTakeBackToFront
		case "xs": self = .storeExtraInhabitant
		case "xg": self = .getExtraInhabitantIndex
		case "ug": self = .getEnumTag
		case "up": self = .destructiveProjectEnumData
		case "ui": self = .destructiveInjectEnumTag
		case "et": self = .getEnumTagSinglePayload
		case "st": self = .storeEnumTagSinglePayload
		default: return nil
		}
	}
	
	var description: String {
		switch self {
		case .allocateBuffer: return "allocateBuffer"
		case .assignWithCopy: return "assignWithCopy"
		case .assignWithTake: return "assignWithTake"
		case .deallocateBuffer: return "deallocateBuffer"
		case .destroy: return "destroy"
		case .destroyBuffer: return "destroyBuffer"
		case .initializeBufferWithCopyOfBuffer: return "initializeBufferWithCopyOfBuffer"
		case .initializeBufferWithCopy: return "initializeBufferWithCopy"
		case .initializeWithCopy: return "initializeWithCopy"
		case .initializeBufferWithTake: return "initializeBufferWithTake"
		case .initializeWithTake: return "initializeWithTake"
		case .projectBuffer: return "projectBuffer"
		case .initializeBufferWithTakeOfBuffer: return "initializeBufferWithTakeOfBuffer"
		case .destroyArray: return "destroyArray"
		case .initializeArrayWithCopy: return "initializeArrayWithCopy"
		case .initializeArrayWithTakeFrontToBack: return "initializeArrayWithTakeFrontToBack"
		case .initializeArrayWithTakeBackToFront: return "initializeArrayWithTakeBackToFront"
		case .storeExtraInhabitant: return "storeExtraInhabitant"
		case .getExtraInhabitantIndex: return "getExtraInhabitantIndex"
		case .getEnumTag: return "getEnumTag"
		case .destructiveProjectEnumData: return "destructiveProjectEnumData"
		case .destructiveInjectEnumTag: return "destructiveInjectEnumTag"
		case .getEnumTagSinglePayload: return "getEnumTagSinglePayload"
		case .storeEnumTagSinglePayload: return "storeEnumTagSinglePayload"
		}
	}
}

public struct SwiftSymbol: Sendable {
	public let kind: Kind
	public var children: [SwiftSymbol]
	public let contents: Contents
	var originalMangling: String?
	
	public enum Contents: Sendable {
		case none
		case index(UInt64)
		case name(String)
	}
	
	public init(kind: Kind, children: [SwiftSymbol] = [], contents: Contents = .none) {
		self.kind = kind
		self.children = children
		self.contents = contents
		self.originalMangling = nil
	}
	
	init(kind: Kind, child: SwiftSymbol) {
		self.init(kind: kind, children: [child], contents: .none)
	}
	
	init(typeWithChildKind: Kind, childChild: SwiftSymbol) {
		self.init(kind: .type, children: [SwiftSymbol(kind: typeWithChildKind, children: [childChild])], contents: .none)
	}
	
	init(typeWithChildKind: Kind, childChildren: [SwiftSymbol]) {
		self.init(kind: .type, children: [SwiftSymbol(kind: typeWithChildKind, children: childChildren)], contents: .none)
	}
	
	init(swiftStdlibTypeKind: Kind, name: String) {
		self.init(kind: .type, children: [SwiftSymbol(kind: swiftStdlibTypeKind, children: [
			SwiftSymbol(kind: .module, contents: .name(stdlibName)),
			SwiftSymbol(kind: .identifier, contents: .name(name))
		])], contents: .none)
	}
	
	init(swiftBuiltinType: Kind, name: String) {
		self.init(kind: .type, children: [SwiftSymbol(kind: swiftBuiltinType, contents: .name(name))])
	}
	
	var text: String? {
		switch contents {
		case .name(let s): return s
		default: return nil
		}
	}
	
	var index: UInt64? {
		switch contents {
		case .index(let i): return i
		default: return nil
		}
	}
	
	var isProtocol: Bool {
		switch kind {
		case .type: return children.first?.isProtocol ?? false
		case .protocol, .protocolSymbolicReference, .objectiveCProtocolSymbolicReference: return true
		default: return false
		}
	}
	
	
	func changeChild(_ newChild: SwiftSymbol?, atIndex: Int) -> SwiftSymbol {
		guard children.indices.contains(atIndex) else { return self }
		
		var modifiedChildren = children
		if let nc = newChild {
			modifiedChildren[atIndex] = nc
		} else {
			modifiedChildren.remove(at: atIndex)
		}
		return SwiftSymbol(kind: kind, children: modifiedChildren, contents: contents)
	}
	
	func changeKind(_ newKind: Kind, additionalChildren: [SwiftSymbol] = []) -> SwiftSymbol {
		if case .name(let text) = contents {
			return SwiftSymbol(kind: newKind, children: children + additionalChildren, contents: .name(text))
		} else if case .index(let i) = contents {
			return SwiftSymbol(kind: newKind, children: children + additionalChildren, contents: .index(i))
		} else {
			return SwiftSymbol(kind: newKind, children: children + additionalChildren, contents: .none)
		}
	}
}
