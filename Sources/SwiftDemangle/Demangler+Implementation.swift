import Foundation

// MARK: Demangler.cpp

extension SwiftSymbol.Kind {
	var isDeclName: Bool {
		switch self {
		case .identifier, .localDeclName, .privateDeclName, .relatedEntityDeclName: fallthrough
		case .prefixOperator, .postfixOperator, .infixOperator: fallthrough
		case .typeSymbolicReference, .protocolSymbolicReference, .objectiveCProtocolSymbolicReference: return true
		default: return false
		}
	}
	
	var isContext: Bool {
		switch self {
		case .borrowAccessor, .mutateAccessor, .yieldingBorrowAccessor, .yieldingMutateAccessor, .propertyWrappedFieldInitAccessor: fallthrough
		case .allocator, .anonymousContext, .autoDiffFunction, .class, .constructor, .curryThunk, .deallocator, .defaultArgumentInitializer: fallthrough
		case .destructor, .didSet, .dispatchThunk, .enum, .explicitClosure, .extension, .function: fallthrough
		case .getter, .globalGetter, .iVarInitializer, .iVarDestroyer, .implicitClosure: fallthrough
		case .initializer, .initAccessor, .isolatedDeallocator, .materializeForSet, .modifyAccessor, .modify2Accessor: fallthrough
		case .module, .nativeOwningAddressor: fallthrough
		case .nativeOwningMutableAddressor, .nativePinningAddressor, .nativePinningMutableAddressor, .opaqueReturnTypeOf: fallthrough
		case .otherNominalType, .owningAddressor, .owningMutableAddressor, .propertyWrapperBackingInitializer: fallthrough
		case .propertyWrapperInitFromProjectedValue, .protocol, .protocolSymbolicReference, .readAccessor: fallthrough
		case .read2Accessor, .setter, .static: fallthrough
		case .structure, .subscript, .typeSymbolicReference, .typeAlias, .unsafeAddressor, .unsafeMutableAddressor: fallthrough
		case .variable, .willSet, .builtinTupleType: return true
		default: return false
		}
	}
	
	var isAnyGeneric: Bool {
		switch self {
		case .structure, .class, .enum, .protocol, .protocolSymbolicReference, .otherNominalType, .typeAlias, .typeSymbolicReference, .objectiveCProtocolSymbolicReference, .builtinTupleType: return true
		default: return false
		}
	}
	
	var isEntity: Bool {
		return self == .type || isContext
	}
	
	var isRequirement: Bool {
		switch self {
		case .dependentGenericParamPackMarker, .dependentGenericParamValueMarker, .dependentGenericSameTypeRequirement, .dependentGenericSameShapeRequirement: fallthrough
		case .dependentGenericLayoutRequirement, .dependentGenericConformanceRequirement, .dependentGenericInverseConformanceRequirement: return true
		default: return false
		}
	}
	
	var isFunctionAttr: Bool {
		switch self {
		case .functionSignatureSpecialization, .genericSpecialization, .genericSpecializationPrespecialized, .inlinedGenericFunction: fallthrough
		case .genericSpecializationNotReAbstracted, .genericPartialSpecialization: fallthrough
		case .genericPartialSpecializationNotReAbstracted, .genericSpecializationInResilienceDomain, .objCAttribute, .nonObjCAttribute: fallthrough
		case .dynamicAttribute, .directMethodReferenceAttribute, .vTableAttribute, .partialApplyForwarder: fallthrough
		case .partialApplyObjCForwarder, .outlinedVariable, .outlinedReadOnlyObject, .outlinedBridgedMethod, .mergedFunction: fallthrough
		case .distributedThunk, .distributedAccessor: fallthrough
		case .dynamicallyReplaceableFunctionImpl, .dynamicallyReplaceableFunctionKey, .dynamicallyReplaceableFunctionVar: fallthrough
		case .asyncFunctionPointer, .asyncAwaitResumePartialFunction, .asyncSuspendResumePartialFunction: fallthrough
		case .accessibleFunctionRecord, .backDeploymentThunk, .backDeploymentFallback, .coroFunctionPointer, .defaultOverride: fallthrough
		case .hasSymbolQuery: return true
		default: return false
		}
	}
}

extension Demangler {
	func require<T>(_ optional: Optional<T>) throws -> T {
		if let v = optional {
			return v
		} else {
			throw failure
		}
	}
	
	func require(_ value: Bool) throws {
		if !value {
			throw failure
		}
	}
	
	var failure: Error {
		return scanner.unexpectedError()
	}
	
	mutating func readManglingPrefix() throws {
		let prefixes = [
			"_T0", "$S", "_$S", "$s", "_$s", "$e", "_$e", "@__swiftmacro_"
		]
		for prefix in prefixes {
			if scanner.conditional(string: prefix) {
				if prefix == "$e" { flavor = .embedded }
				return
			}
		}
		throw scanner.unexpectedError()
	}
	
	mutating func reset() {
		nodeStack = []
		substitutions = []
		words = []
		scanner.reset()
		isOldFunctionTypeMangling = false
		flavor = .default
	}
	
	mutating func popTopLevelInto(_ parent: inout SwiftSymbol) throws {
		while var funcAttr = popNode(where: { $0.isFunctionAttr }) {
			switch funcAttr.kind {
			case .partialApplyForwarder, .partialApplyObjCForwarder:
				try popTopLevelInto(&funcAttr)
				parent.children.append(funcAttr)
				return
			default:
				parent.children.append(funcAttr)
			}
		}
		for name in nodeStack {
			switch name.kind {
			case .type: parent.children.append(try require(name.children.first))
			default: parent.children.append(name)
			}
		}
	}
	
	mutating func demangleSymbol() throws -> SwiftSymbol {
		reset()
		
		if scanner.conditional(string: "_Tt") {
			return try demangleObjCTypeName()
		} else if scanner.conditional(string: "_T") {
			isOldFunctionTypeMangling = true
			try scanner.backtrack(count: 2)
		}
		
		if scanner.conditional(string: "async_Main") || scanner.conditional(string: "_async_Main") {
			nodeStack.append(SwiftSymbol(kind: .asyncMainEntryPoint))
		} else {
			try readManglingPrefix()
		}
		try parseAndPushNodes()
		
		let suffix = popNode(kind: .suffix)
		var topLevel = SwiftSymbol(kind: .global)
		try popTopLevelInto(&topLevel)
		if let suffix {
			topLevel.children.append(suffix)
		}
		try require(topLevel.children.count != 0)
		return topLevel
	}
	
	mutating func demangleType() throws -> SwiftSymbol {
		reset()
		
		try parseAndPushNodes()
		let result = try require(popNode())
		try require(nodeStack.isEmpty)
		return result
	}
	
	mutating func parseAndPushNodes() throws {
		while !scanner.isAtEnd {
			if scanner.peek() == "\0" { return }
			nodeStack.append(try demangleOperator())
		}
	}
	
	mutating func demangleSymbolicReference() throws -> SwiftSymbol {
		let referenceKind = try scanner.readScalar().value
		try require([1, 2, 9, 10, 11, 12].contains(referenceKind))
		let offset = scanner.consumed
		var value: UInt32 = 0
		for byteIndex in 0..<4 {
			let byte = try scanner.readScalar().value
			try require(byte <= UInt8.max)
			value |= byte << (byteIndex * 8)
		}
		let resolver = try require(symbolicReferenceResolver)
		let resolved = try resolver(Int32(bitPattern: value), offset)
		if [1, 2, 12].contains(referenceKind), resolved.kind != .opaqueTypeDescriptorSymbolicReference, resolved.kind != .opaqueReturnTypeOf {
			substitutions.append(resolved)
		}
		return resolved
	}
	
	mutating func demangleTypeAnnotation() throws -> SwiftSymbol {
		switch try scanner.readScalar() {
		case "a": return SwiftSymbol(kind: .asyncAnnotation)
		case "A": return SwiftSymbol(kind: .isolatedAnyFunctionType)
		case "b": return SwiftSymbol(kind: .concurrentFunctionType)
		case "c": return SwiftSymbol(kind: .globalActorFunctionType, child: try require(popTypeAndGetChild()))
		case "i": return SwiftSymbol(typeWithChildKind: .isolated, childChild: try require(popTypeAndGetChild()))
		case "j": return try demangleDifferentiableFunctionType()
		case "k": return SwiftSymbol(typeWithChildKind: .noDerivative, childChild: try require(popTypeAndGetChild()))
		case "K": return SwiftSymbol(kind: .typedThrowsAnnotation, child: try require(popTypeAndGetChild()))
		case "t": return SwiftSymbol(typeWithChildKind: .compileTimeLiteral, childChild: try require(popTypeAndGetChild()))
		case "T": return SwiftSymbol(kind: .sendingResultFunctionType)
		case "u": return SwiftSymbol(typeWithChildKind: .sending, childChild: try require(popTypeAndGetChild()))
		case "C": return SwiftSymbol(kind: .nonIsolatedCallerFunctionType)
		case "g": return SwiftSymbol(typeWithChildKind: .constValue, childChild: try require(popTypeAndGetChild()))
		default: throw failure
		}
	}
	
	mutating func demangleOperator() throws -> SwiftSymbol {
		while scanner.conditional(scalar: "\u{FF}") {}
		switch try scanner.readScalar() {
		case "\u{1}", "\u{2}", "\u{3}", "\u{4}", "\u{5}", "\u{6}", "\u{7}", "\u{8}", "\u{9}", "\u{A}", "\u{B}", "\u{C}":
			try scanner.backtrack()
			return try demangleSymbolicReference()
		case "A": return try demangleMultiSubstitutions()
		case "B": return try demangleBuiltinType()
		case "C": return try demangleAnyGenericType(kind: .class)
		case "D": return try demangleTypeMangling()
		case "E": return try demangleExtensionContext()
		case "F": return try demanglePlainFunction()
		case "G": return try demangleBoundGenericType()
		case "H":
			switch try scanner.readScalar() {
			case "A": return try demangleDependentProtocolConformanceAssociated()
			case "C": return try demangleConcreteProtocolConformance()
			case "D": return try demangleDependentProtocolConformanceRoot()
			case "I": return try demangleDependentProtocolConformanceInherited()
			case "O": return try demangleDependentProtocolConformanceOpaque()
			case "P": return SwiftSymbol(kind: .protocolConformanceRefInTypeModule, child: try popProtocol())
			case "p": return SwiftSymbol(kind: .protocolConformanceRefInProtocolModule, child: try popProtocol())
			case "X": return try demanglePackProtocolConformance()
			case "c": return SwiftSymbol(kind: .protocolConformanceDescriptorRecord, child: try popProtocolConformance())
			case "n": return SwiftSymbol(kind: .nominalTypeDescriptorRecord, child: try require(popNode(kind: .type)))
			case "o": return SwiftSymbol(kind: .opaqueTypeDescriptorRecord, child: try require(popNode()))
			case "r": return SwiftSymbol(kind: .protocolDescriptorRecord, child: try popProtocol())
			case "F": return SwiftSymbol(kind: .accessibleFunctionRecord)
			default:
				try scanner.backtrack(count: 2)
				return try demangleIdentifier()
			}
		case "I": return try demangleImplFunctionType()
		case "K": return SwiftSymbol(kind: .throwsAnnotation)
		case "L": return try demangleLocalIdentifier()
		case "M": return try demangleMetatype()
		case "N": return SwiftSymbol(kind: .typeMetadata, child: try require(popNode(kind: .type)))
		case "O": return try demangleAnyGenericType(kind: .enum)
		case "P": return try demangleAnyGenericType(kind: .protocol)
		case "Q": return try demangleArchetype()
		case "R": return try demangleGenericRequirement()
		case "S": return try demangleStandardSubstitution()
		case "T": return try demangleThunkOrSpecialization()
		case "V": return try demangleAnyGenericType(kind: .structure)
		case "W": return try demangleWitness()
		case "X": return try demangleSpecialType()
		case "Y": return try demangleTypeAnnotation()
		case "Z": return SwiftSymbol(kind: .static, child: try require(popNode(where: { $0.isEntity })))
		case "a": return try demangleAnyGenericType(kind: .typeAlias)
		case "c": return try require(popFunctionType(kind: .functionType))
		case "d": return SwiftSymbol(kind: .variadicMarker)
		case "f": return try demangleFunctionEntity()
		case "g": return try demangleRetroactiveConformance()
		case "h": return SwiftSymbol(typeWithChildKind: .shared, childChild: try require(popTypeAndGetChild()))
		case "i": return try demangleSubscript()
		case "l": return try demangleGenericSignature(hasParamCounts: false)
		case "m": return SwiftSymbol(typeWithChildKind: .metatype, childChild: try require(popNode(kind: .type)))
		case "n": return SwiftSymbol(typeWithChildKind: .owned, childChild: try popTypeAndGetChild())
		case "o": return try demangleOperatorIdentifier();
		case "p": return try demangleProtocolListType();
		case "q": return SwiftSymbol(kind: .type, child: try demangleGenericParamIndex())
		case "r": return try demangleGenericSignature(hasParamCounts: true)
		case "s": return SwiftSymbol(kind: .module, contents: .name(stdlibName))
		case "t": return try popTuple()
		case "u": return try demangleGenericType()
		case "v": return try demangleVariable()
		case "w": return try demangleValueWitness()
		case "x": return SwiftSymbol(kind: .type, child: try getDependentGenericParamType(depth: 0, index: 0))
		case "y": return SwiftSymbol(kind: .emptyList)
		case "z": return SwiftSymbol(typeWithChildKind: .inOut, childChild: try require(popTypeAndGetChild()))
		case "_": return SwiftSymbol(kind: .firstElementMarker)
		case ".":
			try scanner.backtrack()
			return SwiftSymbol(kind: .suffix, contents: .name(scanner.remainder()))
		case "$": return try demangleIntegerType()
		default:
			try scanner.backtrack()
			return try demangleIdentifier()
		}
	}
	
	mutating func demangleTypeMangling() throws -> SwiftSymbol {
		var type = try require(popNode(kind: .type))
		let labels = try popFunctionParamLabels(type: &type)
		return SwiftSymbol(kind: .typeMangling, children: (labels.map { [$0] } ?? []) + [type])
	}

	mutating func demanglePackProtocolConformance() throws -> SwiftSymbol {
		return SwiftSymbol(kind: .packProtocolConformance, child: try popAnyProtocolConformanceList())
	}

	mutating func demangleNatural() throws -> UInt64? {
		let value = try scanner.conditionalInt()
		if let value { try require(value <= UInt64(Int32.max)) }
		return value
	}
	
	mutating func demangleIndex() throws -> UInt64 {
		if scanner.conditional(scalar: "_") {
			return 0
		}
		let value = try require(demangleNatural())
		try scanner.match(scalar: "_")
		try require(value < UInt64(Int32.max))
		return value + 1
	}
	
	mutating func demangleIndexAsNode() throws -> SwiftSymbol {
		return SwiftSymbol(kind: .number, contents: .index(try demangleIndex()))
	}
	
	mutating func demangleMultiSubstitutions() throws -> SwiftSymbol {
		var repeatCount: Int = -1
		while true {
			let c = try scanner.readScalar()
			if c == "\0" {
				throw scanner.unexpectedError()
			} else if c.isLower {
				let nd = try pushMultiSubstitutions(repeatCount: repeatCount, index: Int(c.value - UnicodeScalar("a").value))
				nodeStack.append(nd)
				repeatCount = -1
				continue
			} else if c.isUpper {
				return try pushMultiSubstitutions(repeatCount: repeatCount, index: Int(c.value - UnicodeScalar("A").value))
			} else if c == "_" {
				let idx = Int(repeatCount + 27)
				return try require(substitutions.at(idx))
			} else {
				try scanner.backtrack()
				repeatCount = Int(try require(demangleNatural()))
			}
		}
	}
	
	mutating func pushMultiSubstitutions(repeatCount: Int, index: Int) throws -> SwiftSymbol {
		try require(repeatCount <= maxRepeatCount)
		let nd = try require(substitutions.at(index))
		(0..<max(0, repeatCount - 1)).forEach { _ in nodeStack.append(nd) }
		return nd
	}
	
	mutating func popNode() -> SwiftSymbol? {
		return nodeStack.popLast()
	}
	
	mutating func popNode(kind: SwiftSymbol.Kind) -> SwiftSymbol? {
		return nodeStack.last?.kind == kind ? popNode() : nil
	}
	
	mutating func popNode(where cond: (SwiftSymbol.Kind) -> Bool) -> SwiftSymbol? {
		return nodeStack.last.map({ cond($0.kind) }) == true ? popNode() : nil
	}
	
	mutating func popFunctionType(kind: SwiftSymbol.Kind, hasClangType: Bool = false) throws -> SwiftSymbol {
		var name = SwiftSymbol(kind: kind)
		if hasClangType {
			name.children.append(try demangleClangType())
		}
		if let sendingResult = popNode(kind: .sendingResultFunctionType) {
			name.children.append(sendingResult)
		}
		if let isFunctionIsolation = popNode(where: { $0 == .globalActorFunctionType || $0 == .isolatedAnyFunctionType || $0 == .nonIsolatedCallerFunctionType }) {
			name.children.append(isFunctionIsolation)
		}
		if let differentiable = popNode(kind: .differentiableFunctionType) {
			name.children.append(differentiable)
		}
		if let throwsAnnotation = popNode(where: { $0 == .throwsAnnotation || $0 == .typedThrowsAnnotation}) {
			name.children.append(throwsAnnotation)
		}
		if let concurrent = popNode(kind: .concurrentFunctionType) {
			name.children.append(concurrent)
		}
		if let asyncAnnotation = popNode(kind: .asyncAnnotation) {
			name.children.append(asyncAnnotation)
		}
		name.children.append(try popFunctionParams(kind: .argumentTuple))
		if let yields = popNode(kind: .yieldTypes) {
			name.children.append(yields)
		}
		name.children.append(try popFunctionParams(kind: .returnType))
		return SwiftSymbol(kind: .type, child: name)
	}
	
	mutating func popFunctionParams(kind: SwiftSymbol.Kind) throws -> SwiftSymbol {
		let paramsType: SwiftSymbol
		if popNode(kind: .emptyList) != nil {
			return SwiftSymbol(kind: kind, child: SwiftSymbol(kind: .type, child: SwiftSymbol(kind: .tuple)))
		} else {
			paramsType = try require(popNode(kind: .type))
		}
		
		return SwiftSymbol(kind: kind, child: paramsType)
	}
	
	mutating func getLabel(params: inout SwiftSymbol, idx: Int) throws -> SwiftSymbol {
		if isOldFunctionTypeMangling {
			let param = try require(params.children.at(idx))
			if let label = param.children.enumerated().first(where: { $0.element.kind == .tupleElementName }) {
				params.children[idx].children.remove(at: label.offset)
				return SwiftSymbol(kind: .identifier, contents: .name(label.element.text ?? ""))
			}
			return SwiftSymbol(kind: .firstElementMarker)
		}
		return try require(popNode())
	}
	
	mutating func popFunctionParamLabels(type: inout SwiftSymbol) throws -> SwiftSymbol? {
		if !isOldFunctionTypeMangling && popNode(kind: .emptyList) != nil {
			return SwiftSymbol(kind: .labelList)
		}
		
		guard type.kind == .type else { return nil }
		
		let topFuncType = try require(type.children.first)
		let funcType: SwiftSymbol
		if topFuncType.kind == .dependentGenericType {
			funcType = try require(topFuncType.children.at(1)?.children.first)
		} else {
			funcType = topFuncType
		}
		
		guard funcType.kind == .functionType || funcType.kind == .noEscapeFunctionType || funcType.kind == .calledOnceFunctionType else { return nil }
		
		var firstChildIndex = 0
		if funcType.children.at(firstChildIndex)?.kind == .sendingResultFunctionType {
			firstChildIndex += 1
		}
		if funcType.children.at(firstChildIndex)?.kind == .globalActorFunctionType {
			firstChildIndex += 1
		}
		if funcType.children.at(firstChildIndex)?.kind == .isolatedAnyFunctionType {
			firstChildIndex += 1
		}
		if funcType.children.at(firstChildIndex)?.kind == .nonIsolatedCallerFunctionType {
			firstChildIndex += 1
		}
		if funcType.children.at(firstChildIndex)?.kind == .differentiableFunctionType {
			firstChildIndex += 1
		}
		if funcType.children.at(firstChildIndex)?.kind == .throwsAnnotation || funcType.children.at(firstChildIndex)?.kind == .typedThrowsAnnotation {
			firstChildIndex += 1
		}
		if funcType.children.at(firstChildIndex)?.kind == .concurrentFunctionType {
			firstChildIndex += 1
		}
		if funcType.children.at(firstChildIndex)?.kind == .asyncAnnotation {
			firstChildIndex += 1
		}
		
		let parameterType = try require(funcType.children.at(firstChildIndex))
		try require(parameterType.kind == .argumentTuple)
		
		let paramsType = try require(parameterType.children.first)
		try require(paramsType.kind == .type)
		
		let params = paramsType.children.first
		let numParams = params?.kind == .tuple ? (params?.children.count ?? 0) : 1
		
		guard numParams > 0 else { return nil }
		
		let possibleTuple = parameterType.children.first?.children.first
		if isOldFunctionTypeMangling && possibleTuple?.kind != .tuple { return SwiftSymbol(kind: .labelList) }
		var tuple = try require(possibleTuple)
		defer {
			if isOldFunctionTypeMangling {
				if topFuncType.kind == .dependentGenericType {
					type.children[0].children[1].children[0].children[firstChildIndex].children[0].children[0] = tuple
				} else {
					type.children[0].children[firstChildIndex].children[0].children[0] = tuple
				}
			}
		}
		
		var hasLabels = false
		var children = [SwiftSymbol]()
		for i in 0..<numParams {
			let label = try getLabel(params: &tuple, idx: Int(i))
			try require(label.kind == .identifier || label.kind == .firstElementMarker)
			children.append(label)
			hasLabels = hasLabels || (label.kind != .firstElementMarker)
		}
		
		if !hasLabels {
			return SwiftSymbol(kind: .labelList)
		}
		
		return SwiftSymbol(kind: .labelList, children: isOldFunctionTypeMangling ? children : children.reversed())
	}
	
	mutating func popTuple() throws -> SwiftSymbol {
		var children: [SwiftSymbol] = []
		if popNode(kind: .emptyList) == nil {
			var firstElem = false
			repeat {
				firstElem = popNode(kind: .firstElementMarker) != nil
				var elemChildren: [SwiftSymbol] = popNode(kind: .variadicMarker).map { [$0] } ?? []
				if let ident = popNode(kind: .identifier), case .name(let text) = ident.contents {
					elemChildren.append(SwiftSymbol(kind: .tupleElementName, contents: .name(text)))
				}
				elemChildren.append(try require(popNode(kind: .type)))
				children.insert(SwiftSymbol(kind: .tupleElement, children: elemChildren), at: 0)
			} while (!firstElem)
		}
		return SwiftSymbol(typeWithChildKind: .tuple, childChildren: children)
	}
	
	mutating func popPack(kind: SwiftSymbol.Kind = .pack) throws -> SwiftSymbol {
		if popNode(kind: .emptyList) != nil {
			return SwiftSymbol(kind: .type, child: SwiftSymbol(kind: kind))
		}
		var firstElem = false
		var children = [SwiftSymbol]()
		repeat {
			firstElem = popNode(kind: .firstElementMarker) != nil
			try children.append(require(popNode(kind: .type)))
		} while !firstElem
		children.reverse()
		return SwiftSymbol(kind: .type, child: SwiftSymbol(kind: kind, children: children))
	}
	
	mutating func popSILPack() throws -> SwiftSymbol {
		switch try scanner.readScalar() {
		case "d": return try popPack(kind: .silPackDirect)
		case "i": return try popPack(kind: .silPackIndirect)
		default: throw failure
		}
	}
	
	mutating func popTypeList() throws -> SwiftSymbol {
		var children: [SwiftSymbol] = []
		if popNode(kind: .emptyList) == nil {
			var firstElem = false
			repeat {
				firstElem = popNode(kind: .firstElementMarker) != nil
				children.insert(try require(popNode(kind: .type)), at: 0)
			} while (!firstElem)
		}
		return SwiftSymbol(kind: .typeList, children: children)
	}
	
	mutating func popProtocol() throws -> SwiftSymbol {
		if let type = popNode(kind: .type) {
			try require(type.children.at(0)?.isProtocol == true)
			return type
		}
		
		if let symbolicRef = popNode(kind: .protocolSymbolicReference) {
			return symbolicRef
		} else if let symbolicRef = popNode(kind: .objectiveCProtocolSymbolicReference) {
			return symbolicRef
		}
		
		let name = try require(popNode { $0.isDeclName })
		let context = try popContext()
		return SwiftSymbol(typeWithChildKind: .protocol, childChildren: [context, name])
	}
	
	mutating func popAnyProtocolConformanceList() throws -> SwiftSymbol {
		var conformanceList = SwiftSymbol(kind: .anyProtocolConformanceList)
		if popNode(kind: .emptyList) == nil {
			var firstElem = false
			repeat {
				firstElem = popNode(kind: .firstElementMarker) != nil
				conformanceList.children.append(try require(popAnyProtocolConformance()))
			} while !firstElem
			conformanceList.children = conformanceList.children.reversed()
		}
		return conformanceList
	}
	
	mutating func popAnyProtocolConformance() -> SwiftSymbol? {
		return popNode { kind in
			switch kind {
			case .concreteProtocolConformance, .packProtocolConformance, .dependentProtocolConformanceRoot, .dependentProtocolConformanceInherited, .dependentProtocolConformanceAssociated, .dependentProtocolConformanceOpaque: return true
			default: return false
			}
		}
	}
	
	mutating func demangleRetroactiveProtocolConformanceRef() throws -> SwiftSymbol {
		let module = try require(popModule())
		let proto = try require(popProtocol())
		return SwiftSymbol(kind: .protocolConformanceRefInOtherModule, children: [proto, module])
	}
	
	mutating func demangleConcreteProtocolConformance() throws -> SwiftSymbol {
		let conditionalConformanceList = try require(popAnyProtocolConformanceList())
		let conformanceRef = try popNode(kind: .protocolConformanceRefInTypeModule) ?? popNode(kind: .protocolConformanceRefInProtocolModule) ?? demangleRetroactiveProtocolConformanceRef()
		return SwiftSymbol(kind: .concreteProtocolConformance, children: [try require(popNode(kind: .type)), conformanceRef, conditionalConformanceList])
	}
	
	mutating func popDependentProtocolConformance() -> SwiftSymbol? {
		return popNode { kind in
			switch kind {
			case .dependentProtocolConformanceRoot, .dependentProtocolConformanceInherited, .dependentProtocolConformanceAssociated, .dependentProtocolConformanceOpaque: return true
			default: return false
			}
		}
	}
	
	mutating func demangleDependentProtocolConformanceRoot() throws -> SwiftSymbol {
		let index = try demangleDependentConformanceIndex()
		let prot = try popProtocol()
		return SwiftSymbol(kind: .dependentProtocolConformanceRoot, children: [try require(popNode(kind: .type)), prot, index])
	}
	
	mutating func demangleDependentProtocolConformanceInherited() throws -> SwiftSymbol {
		let index = try demangleDependentConformanceIndex()
		let prot = try popProtocol()
		let nested = try require(popDependentProtocolConformance())
		return SwiftSymbol(kind: .dependentProtocolConformanceInherited, children: [nested, prot, index])
	}
	
	mutating func popDependentAssociatedConformance() throws -> SwiftSymbol {
		let prot = try popProtocol()
		let dependentType = try require(popNode(kind: .type))
		return SwiftSymbol(kind: .dependentAssociatedConformance, children: [dependentType, prot])
	}
	
	mutating func demangleDependentProtocolConformanceAssociated() throws -> SwiftSymbol {
		let index = try demangleDependentConformanceIndex()
		let assoc = try popDependentAssociatedConformance()
		let nested = try require(popDependentProtocolConformance())
		return SwiftSymbol(kind: .dependentProtocolConformanceAssociated, children: [nested, assoc, index])
	}

	mutating func demangleDependentProtocolConformanceOpaque() throws -> SwiftSymbol {
		let type = try require(popNode(kind: .type))
		let conformance = try require(popDependentProtocolConformance())
		return SwiftSymbol(kind: .dependentProtocolConformanceOpaque, children: [conformance, type])
	}
	
	mutating func demangleDependentConformanceIndex() throws -> SwiftSymbol {
		let index = try demangleIndex()
		if index == 1 {
			return SwiftSymbol(kind: .unknownIndex)
		}
		return SwiftSymbol(kind: .index, contents: .index(index - 2))
	}
	
	mutating func popModule() -> SwiftSymbol? {
		if let ident = popNode(kind: .identifier) {
			return ident.changeKind(.module)
		} else {
			return popNode(kind: .module)
		}
	}
	
	mutating func popContext() throws -> SwiftSymbol {
		if let mod = popModule() {
			return mod
		} else if let type = popNode(kind: .type) {
			let child = try require(type.children.first)
			try require(child.kind.isContext)
			return child
		}
		return try require(popNode { $0.isContext })
	}
	
	mutating func popTypeAndGetChild() throws -> SwiftSymbol {
		return try require(popNode(kind: .type)?.children.first)
	}
	
	mutating func popTypeAndGetAnyGeneric() throws -> SwiftSymbol {
		let child = try popTypeAndGetChild()
		try require(child.kind.isAnyGeneric)
		return child
	}
	
	mutating func popAssocTypeName() throws -> SwiftSymbol {
		let maybeProto = popNode(kind: .type)
		let proto: SwiftSymbol?
		if let p = maybeProto {
			try require(p.isProtocol)
			proto = p
		} else {
			proto = popNode(kind: .protocolSymbolicReference) ?? popNode(kind: .objectiveCProtocolSymbolicReference)
		}
		
		let id = try require(popNode(kind: .identifier))
		if let p = proto {
			return SwiftSymbol(kind: .dependentAssociatedTypeRef, children: [id, p])
		} else {
			return SwiftSymbol(kind: .dependentAssociatedTypeRef, child: id)
		}
	}
	
	mutating func popAssocTypePath() throws -> SwiftSymbol {
		var firstElem = false
		var assocTypePath = [SwiftSymbol]()
		repeat {
			firstElem = popNode(kind: .firstElementMarker) != nil
			assocTypePath.append(try require(popAssocTypeName()))
		} while !firstElem
		return SwiftSymbol(kind: .assocTypePath, children: assocTypePath.reversed())
	}
	
	mutating func popProtocolConformance() throws -> SwiftSymbol {
		let genSig = popNode(kind: .dependentGenericSignature)
		let module = try require(popModule())
		let proto = try popProtocol()
		var type = popNode(kind: .type)
		var ident: SwiftSymbol? = nil
		if type == nil {
			ident = popNode(kind: .identifier)
			type = popNode(kind: .type)
		}
		if let gs = genSig {
			type = SwiftSymbol(typeWithChildKind: .dependentGenericType, childChildren: [gs, try require(type)])
		}
		var children = [try require(type), proto, module]
		if let i = ident {
			children.append(i)
		}
		return SwiftSymbol(kind: .protocolConformance, children: children)
	}
	
	mutating func getDependentGenericParamType(depth: Int, index: Int) throws -> SwiftSymbol {
		try require(depth >= 0 && index >= 0)

		return SwiftSymbol(kind: .dependentGenericParamType, children: [
			SwiftSymbol(kind: .index, contents: .index(UInt64(depth))),
			SwiftSymbol(kind: .index, contents: .index(UInt64(index)))
		])
	}
	
	mutating func demangleStandardSubstitution() throws -> SwiftSymbol {
		switch try scanner.readScalar() {
		case "o": return SwiftSymbol(kind: .module, contents: .name(objcModule))
		case "C": return SwiftSymbol(kind: .module, contents: .name(cModule))
		case "g":
			let op = SwiftSymbol(typeWithChildKind: .boundGenericEnum, childChildren: [
				SwiftSymbol(swiftStdlibTypeKind: .enum, name: "Optional"),
				SwiftSymbol(kind: .typeList, child: try require(popNode(kind: .type)))
			])
			substitutions.append(op)
			return op
		default:
			try scanner.backtrack()
			let repeatCount = try demangleNatural() ?? 0
			try require(repeatCount <= maxRepeatCount)
			let secondLevel = scanner.conditional(scalar: "c")
			let nd: SwiftSymbol
			if secondLevel {
				switch try scanner.readScalar() {
				case "A": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "Actor")
				case "C": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "CheckedContinuation")
				case "c": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "UnsafeContinuation")
				case "E": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "CancellationError")
				case "e": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "UnownedSerialExecutor")
				case "F": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "Executor")
				case "f": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "SerialExecutor")
				case "G": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "TaskGroup")
				case "g": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "ThrowingTaskGroup")
				case "h": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "TaskExecutor")
				case "I": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "AsyncIteratorProtocol")
				case "i": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "AsyncSequence")
				case "J": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "UnownedJob")
				case "M": nd = SwiftSymbol(swiftStdlibTypeKind: .class, name: "MainActor")
				case "P": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "TaskPriority")
				case "S": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "AsyncStream")
				case "s": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "AsyncThrowingStream")
				case "T": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "Task")
				case "t": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "UnsafeCurrentTask")
				default: throw failure
				}
			} else {
				switch try scanner.readScalar() {
				case "a": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "Array")
				case "A": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "AutoreleasingUnsafeMutablePointer")
				case "b": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "Bool")
				case "c": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "UnicodeScalar")
				case "D": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "Dictionary")
				case "d": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "Double")
				case "f": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "Float")
				case "h": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "Set")
				case "I": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "DefaultIndices")
				case "i": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "Int")
				case "J": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "Character")
				case "N": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "ClosedRange")
				case "n": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "Range")
				case "O": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "ObjectIdentifier")
				case "p": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "UnsafeMutablePointer")
				case "P": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "UnsafePointer")
				case "R": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "UnsafeBufferPointer")
				case "r": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "UnsafeMutableBufferPointer")
				case "S": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "String")
				case "s": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "Substring")
				case "u": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "UInt")
				case "v": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "UnsafeMutableRawPointer")
				case "V": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "UnsafeRawPointer")
				case "W": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "UnsafeRawBufferPointer")
				case "w": nd = SwiftSymbol(swiftStdlibTypeKind: .structure, name: "UnsafeMutableRawBufferPointer")
					
				case "q": nd = SwiftSymbol(swiftStdlibTypeKind: .enum, name: "Optional")
					
				case "B": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "BinaryFloatingPoint")
				case "E": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "Encodable")
				case "e": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "Decodable")
				case "F": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "FloatingPoint")
				case "G": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "RandomNumberGenerator")
				case "H": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "Hashable")
				case "j": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "Numeric")
				case "K": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "BidirectionalCollection")
				case "k": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "RandomAccessCollection")
				case "L": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "Comparable")
				case "l": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "Collection")
				case "M": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "MutableCollection")
				case "m": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "RangeReplaceableCollection")
				case "Q": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "Equatable")
				case "T": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "Sequence")
				case "t": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "IteratorProtocol")
				case "U": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "UnsignedInteger")
				case "X": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "RangeExpression")
				case "x": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "Strideable")
				case "Y": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "RawRepresentable")
				case "y": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "StringProtocol")
				case "Z": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "SignedInteger")
				case "z": nd = SwiftSymbol(swiftStdlibTypeKind: .protocol, name: "BinaryInteger")
				default: throw failure
				}
			}
			if repeatCount > 1 {
				for _ in 0..<(repeatCount - 1) {
					nodeStack.append(nd)
				}
			}
			return nd
		}
	}
	
	mutating func demangleIdentifier() throws -> SwiftSymbol {
		var hasWordSubs = false
		var isPunycoded = false
		let c = try scanner.read(where: { $0.isDigit })
		if c == "0" {
			if try scanner.readScalar() == "0" {
				isPunycoded = true
			} else {
				try scanner.backtrack()
				hasWordSubs = true
			}
		} else {
			try scanner.backtrack()
		}
		
		var identifier = ""
		repeat {
			while hasWordSubs && scanner.peek()?.isLetter == true {
				let c = try scanner.readScalar()
				var wordIndex = 0
				if c.isLower {
					wordIndex = Int(c.value - UnicodeScalar("a").value)
				} else {
					wordIndex = Int(c.value - UnicodeScalar("A").value)
					hasWordSubs = false
				}
				try require(wordIndex < maxNumWords)
				identifier.append(try require(words.at(wordIndex)))
			}
			if scanner.conditional(scalar: "0") {
				break
			}
			let numChars = try require(demangleNatural())
			try require(numChars > 0)
			if isPunycoded {
				_ = scanner.conditional(scalar: "_")
			}
			let text = try scanner.readUTF8(count: Int(numChars))
			if isPunycoded {
				try identifier.append(Punycode.decodePunycodeUTF8(text))
			} else {
				identifier.append(text)
				var word: String?
				for c in text.unicodeScalars {
					if word == nil, !c.isDigit && c != "_" && words.count < maxNumWords {
						word = "\(c)"
					} else if let w = word {
						if (c == "_") || (w.unicodeScalars.last?.isUpper == false && c.isUpper) {
							if w.unicodeScalars.count >= 2 {
								words.append(w)
							}
							if !c.isDigit && c != "_" && words.count < maxNumWords {
								word = "\(c)"
							} else {
								word = nil
							}
						} else {
							word?.unicodeScalars.append(c)
						}
					}
				}
				if let w = word, w.unicodeScalars.count >= 2 {
					words.append(w)
				}
			}
		} while hasWordSubs
		try require(!identifier.isEmpty)
		let result = SwiftSymbol(kind: .identifier, contents: .name(identifier))
		substitutions.append(result)
		return result
	}
	
	mutating func demangleOperatorIdentifier() throws -> SwiftSymbol {
		let ident = try require(popNode(kind: .identifier))
		let opCharTable = Array("& @/= >    <*!|+?%-~   ^ .".unicodeScalars)
		
		var str = ""
		for c in (try require(ident.text)).unicodeScalars {
			if !c.isASCII {
				str.unicodeScalars.append(c)
			} else {
				try require(c.isLower)
				let o = try require(opCharTable.at(Int(c.value - UnicodeScalar("a").value)))
				try require(o != " ")
				str.unicodeScalars.append(o)
			}
		}
		switch try scanner.readScalar() {
		case "i": return SwiftSymbol(kind: .infixOperator, contents: .name(str))
		case "p": return SwiftSymbol(kind: .prefixOperator, contents: .name(str))
		case "P": return SwiftSymbol(kind: .postfixOperator, contents: .name(str))
		default: throw failure
		}
	}
	
	mutating func demangleLocalIdentifier() throws -> SwiftSymbol {
		let c = try scanner.readScalar()
		switch c {
		case "L":
			let discriminator = try require(popNode(kind: .identifier))
			let name = try require(popNode(where: { $0.isDeclName }))
			return SwiftSymbol(kind: .privateDeclName, children: [discriminator, name])
		case "l":
			let discriminator = try require(popNode(kind: .identifier))
			return SwiftSymbol(kind: .privateDeclName, children: [discriminator])
		case "a"..."j", "A"..."J":
			return SwiftSymbol(kind: .relatedEntityDeclName, children: [SwiftSymbol(kind: .identifier, contents: .name(String(c))), try require(popNode())])
		default:
			try scanner.backtrack()
			let discriminator = try demangleIndexAsNode()
			let name = try require(popNode(where: { $0.isDeclName }))
			return SwiftSymbol(kind: .localDeclName, children: [discriminator, name])
		}
	}
	
	mutating func demangleBuiltinType() throws -> SwiftSymbol {
		let maxTypeSize: UInt64 = 4096
		switch try scanner.readScalar() {
		case "b": return SwiftSymbol(swiftBuiltinType: .builtinTypeName, name: "Builtin.BridgeObject")
		case "B": return SwiftSymbol(swiftBuiltinType: .builtinTypeName, name: "Builtin.UnsafeValueBuffer")
		case "A": return SwiftSymbol(swiftBuiltinType: .builtinTypeName, name: "Builtin.ImplicitActor")
		case "e": return SwiftSymbol(swiftBuiltinType: .builtinTypeName, name: "Builtin.Executor")
		case "f":
			let sizeIndex = try demangleIndex()
			try require(sizeIndex > 0)
			let size = sizeIndex - 1
			try require(size > 0 && size <= maxTypeSize)
			return SwiftSymbol(swiftBuiltinType: .builtinTypeName, name: "Builtin.FPIEEE\(size)")
		case "i":
			let sizeIndex = try demangleIndex()
			try require(sizeIndex > 0)
			let size = sizeIndex - 1
			try require(size > 0 && size <= maxTypeSize)
			return SwiftSymbol(swiftBuiltinType: .builtinTypeName, name: "Builtin.Int\(size)")
		case "W": return SwiftSymbol(typeWithChildKind: .builtinBorrow, childChild: try require(popNode(kind: .type)))
		case "I": return SwiftSymbol(swiftBuiltinType: .builtinTypeName, name: "Builtin.IntLiteral")
		case "v":
			let eltsIndex = try demangleIndex()
			try require(eltsIndex > 0)
			let elts = eltsIndex - 1
			try require(elts > 0 && elts <= maxTypeSize)
			let eltType = try popTypeAndGetChild()
			let text = try require(eltType.text)
			try require(eltType.kind == .builtinTypeName && text.starts(with: "Builtin.") == true)
			let name = text["Builtin.".endIndex...]
			return SwiftSymbol(swiftBuiltinType: .builtinTypeName, name: "Builtin.Vec\(elts)x\(name)")
		case "V":
			let element = try require(popNode(kind: .type))
			let size = try require(popNode(kind: .type))
			return SwiftSymbol(typeWithChildKind: .builtinFixedArray, childChildren: [size, element])
		case "O": return SwiftSymbol(swiftBuiltinType: .builtinTypeName, name: "Builtin.UnknownObject")
		case "o": return SwiftSymbol(swiftBuiltinType: .builtinTypeName, name: "Builtin.NativeObject")
		case "j": return SwiftSymbol(swiftBuiltinType: .builtinTypeName, name: "Builtin.Job")
		case "D": return SwiftSymbol(swiftBuiltinType: .builtinTypeName, name: "Builtin.DefaultActorStorage")
		case "d": return SwiftSymbol(swiftBuiltinType: .builtinTypeName, name: "Builtin.NonDefaultDistributedActorStorage")
		case "c": return SwiftSymbol(swiftBuiltinType: .builtinTypeName, name: "Builtin.RawUnsafeContinuation")
		case "P": return SwiftSymbol(swiftBuiltinType: .builtinTypeName, name: "Builtin.PackIndex")
		case "T": return SwiftSymbol(typeWithChildKind: .builtinTupleType, childChildren: [])
		case "p": return SwiftSymbol(swiftBuiltinType: .builtinTypeName, name: "Builtin.RawPointer")
		case "t": return SwiftSymbol(swiftBuiltinType: .builtinTypeName, name: "Builtin.SILToken")
		case "w": return SwiftSymbol(swiftBuiltinType: .builtinTypeName, name: "Builtin.Word")
		default: throw failure
		}
	}
	
	mutating func demangleAnyGenericType(kind: SwiftSymbol.Kind) throws -> SwiftSymbol {
		let name = try require(popNode(where: { $0.isDeclName }))
		let ctx = try popContext()
		let type = SwiftSymbol(typeWithChildKind: kind, childChildren: [ctx, name])
		substitutions.append(type)
		return type
	}
	
	mutating func demangleExtensionContext() throws -> SwiftSymbol {
		let genSig = popNode(kind: .dependentGenericSignature)
		let module = try require(popModule())
		let type = try popTypeAndGetAnyGeneric()
		if let g = genSig {
			return SwiftSymbol(kind: .extension, children: [module, type, g])
		} else {
			return SwiftSymbol(kind: .extension, children: [module, type])
		}
	}
	
	enum ManglingFlavor {
		case `default`
		case embedded
	}
	
	func getParentID(parent: SwiftSymbol, flavor: ManglingFlavor) -> String {
		// Upstream uses mangleNode(parent, flavor); canonical parent IDs require remangling.
		return "{ParentId}"
	}
	
	mutating func setParentForOpaqueReturnTypeNodes(visited: inout SwiftSymbol, parentId: String) {
		if visited.kind == .opaqueReturnType {
			if visited.children.last?.kind == .opaqueReturnTypeParent {
				return
			}
			visited.children.append(SwiftSymbol(kind: .opaqueReturnTypeParent, contents: .name((parentId))))
			return
		}
		
		switch visited.kind {
		case .function, .variable, .subscript: return
		default: break
		}
		
		for index in visited.children.indices {
			setParentForOpaqueReturnTypeNodes(visited: &visited.children[index], parentId: parentId)
		}
	}
	
	mutating func demanglePlainFunction() throws -> SwiftSymbol {
		let genSig = popNode(kind: .dependentGenericSignature)
		var type = try popFunctionType(kind: .functionType)
		let labelList = try popFunctionParamLabels(type: &type)
		
		if let g = genSig {
			type = SwiftSymbol(typeWithChildKind: .dependentGenericType, childChildren: [g, type])
		}
		let name = try require(popNode(where: { $0.isDeclName }))
		let ctx = try popContext()
		if let ll = labelList {
			return SwiftSymbol(kind: .function, children: [ctx, name, ll, type])
		}
		return SwiftSymbol(kind: .function, children: [ctx, name, type])
	}
	
	mutating func demangleRetroactiveConformance() throws -> SwiftSymbol {
		let index = try demangleIndexAsNode()
		let conformance = try require(popAnyProtocolConformance())
		return SwiftSymbol(kind: .retroactiveConformance, children: [index, conformance])
	}
	
	mutating func demangleBoundGenericType() throws -> SwiftSymbol {
		let (array, retroactiveConformances) = try demangleBoundGenerics()
		let nominal = try popTypeAndGetAnyGeneric()
		var boundNode = try demangleBoundGenericArgs(nominal: nominal, array: array, index: 0)
		if !retroactiveConformances.isEmpty {
			boundNode.children.append(SwiftSymbol(kind: .typeList, children: retroactiveConformances))
		}
		let type = SwiftSymbol(kind: .type, child: boundNode)
		substitutions.append(type)
		return type
	}
	
	mutating func popRetroactiveConformances() throws -> SwiftSymbol? {
		var retroactiveConformances: [SwiftSymbol] = []
		while let conformance = popNode(kind: .retroactiveConformance) {
			retroactiveConformances.append(conformance)
		}
		retroactiveConformances = retroactiveConformances.reversed()
		return retroactiveConformances.isEmpty ? nil : SwiftSymbol(kind: .typeList, children: retroactiveConformances)
	}
	
	mutating func demangleBoundGenerics() throws -> (typeLists: [SwiftSymbol], conformances: [SwiftSymbol]) {
		let retroactiveConformances = try popRetroactiveConformances()
		
		var array = [SwiftSymbol]()
		while true {
			var children = [SwiftSymbol]()
			while let t = popNode(kind: .type) {
				children.append(t)
			}
			array.append(SwiftSymbol(kind: .typeList, children: children.reversed()))
			
			if popNode(kind: .emptyList) != nil {
				break
			} else {
				_ = try require(popNode(kind: .firstElementMarker))
			}
		}
		
		return (array, retroactiveConformances?.children ?? [])
	}
	
	mutating func demangleBoundGenericArgs(nominal: SwiftSymbol, array: [SwiftSymbol], index: Int) throws -> SwiftSymbol {
		if nominal.kind == .typeSymbolicReference || nominal.kind == .protocolSymbolicReference {
			try require(array.indices.contains(index))
			let remaining = array[index...].reversed().flatMap { $0.children }
			return SwiftSymbol(kind: .boundGenericOtherNominalType, children: [SwiftSymbol(kind: .type, child: nominal), SwiftSymbol(kind: .typeList, children: remaining)])
		}
		
		let context = try require(nominal.children.first)
		
		let consumesGenericArgs: Bool
		switch nominal.kind {
		case .variable, .subscript, .implicitClosure, .explicitClosure, .defaultArgumentInitializer, .initializer, .propertyWrapperBackingInitializer, .propertyWrappedFieldInitAccessor, .propertyWrapperInitFromProjectedValue, .static:
			consumesGenericArgs = false
		default:
			consumesGenericArgs = true
		}
		
		let args = try require(array.at(index))
		
		let n: SwiftSymbol
		let offsetIndex = index + (consumesGenericArgs ? 1 : 0)
		if offsetIndex < array.count {
			var boundParent: SwiftSymbol
			if context.kind == .extension {
				let p = try demangleBoundGenericArgs(nominal: try require(context.children.at(1)), array: array, index: offsetIndex)
				boundParent = SwiftSymbol(kind: .extension, children: [try require(context.children.first), p])
				if let thirdChild = context.children.at(2) {
					boundParent.children.append(thirdChild)
				}
			} else {
				boundParent = try demangleBoundGenericArgs(nominal: context, array: array, index: offsetIndex)
			}
			n = SwiftSymbol(kind: nominal.kind, children: [boundParent] + nominal.children.dropFirst())
		} else {
			n = nominal
		}
		
		if !consumesGenericArgs || args.children.count == 0 {
			return n
		}
		
		let kind: SwiftSymbol.Kind
		switch n.kind {
		case .class: kind = .boundGenericClass
		case .structure: kind = .boundGenericStructure
		case .enum: kind = .boundGenericEnum
		case .protocol: kind = .boundGenericProtocol
		case .otherNominalType: kind = .boundGenericOtherNominalType
		case .typeAlias: kind = .boundGenericTypeAlias
		case .function, .constructor: return SwiftSymbol(kind: .boundGenericFunction, children: [n, args])
		default: throw failure
		}
		
		return SwiftSymbol(kind: kind, children: [SwiftSymbol(kind: .type, child: n), args])
	}
	
	mutating func demangleImplParamConvention(kind: SwiftSymbol.Kind) throws -> SwiftSymbol? {
		let attr: String
		switch try scanner.readScalar() {
		case "i": attr = "@in"
		case "c": attr = "@in_constant"
		case "l": attr = "@inout"
		case "b": attr = "@inout_aliasable"
		case "n": attr = "@in_guaranteed"
		case "X": attr = "@in_cxx"
		case "x": attr = "@owned"
		case "g": attr = "@guaranteed"
		case "e": attr = "@deallocating"
		case "y": attr = "@unowned"
		case "v": attr = "@pack_owned"
		case "p": attr = "@pack_guaranteed"
		case "m": attr = "@pack_inout"
		default:
			try scanner.backtrack()
			return nil
		}
		return SwiftSymbol(kind: kind, child: SwiftSymbol(kind: .implConvention, contents: .name(attr)))
	}
	
	mutating func demangleImplResultConvention(kind: SwiftSymbol.Kind) throws -> SwiftSymbol? {
		let attr: String
		switch try scanner.readScalar() {
		case "r": attr = "@out"
		case "o": attr = "@owned"
		case "d": attr = "@unowned"
		case "u": attr = "@unowned_inner_pointer"
		case "a": attr = "@autoreleased"
		case "k": attr = "@pack_out"
		case "l": attr = "@guaranteed_address"
		case "g": attr = "@guaranteed"
		case "m": attr = "@inout"
		default:
			try scanner.backtrack()
			return nil
		}
		return SwiftSymbol(kind: kind, child: SwiftSymbol(kind: .implConvention, contents: .name(attr)))
	}
	
	mutating func demangleImplParameterSending() -> SwiftSymbol? {
		guard scanner.conditional(scalar: "T") else {
			return nil
		}
		return SwiftSymbol(kind: .implParameterSending, contents: .name("sending"))
	}

	mutating func demangleImplParameterIsolated() -> SwiftSymbol? {
		guard scanner.conditional(scalar: "I") else { return nil }
		return SwiftSymbol(kind: .implParameterIsolated, contents: .name("isolated"))
	}

	mutating func demangleImplParameterImplicitLeading() -> SwiftSymbol? {
		guard scanner.conditional(scalar: "L") else { return nil }
		return SwiftSymbol(kind: .implParameterImplicitLeading, contents: .name("sil_implicit_leading_param"))
	}
	
	mutating func demangleImplParameterResultDifferentiability() -> SwiftSymbol {
		return SwiftSymbol(kind: .implParameterResultDifferentiability, contents: .name(scanner.conditional(scalar: "w") ? "@noDerivative" : ""))
	}
	
	mutating func demangleClangType() throws -> SwiftSymbol {
		let numChars = try require(demangleNatural())
		try require(numChars > 0)
		let text = try scanner.readUTF8(count: Int(numChars))
		return SwiftSymbol(kind: .clangType, contents: .name(text))
	}
	
	mutating func demangleImplFunctionType() throws -> SwiftSymbol {
		var typeChildren = [SwiftSymbol]()
		if scanner.conditional(scalar: "s") {
			let (substitutions, conformances) = try demangleBoundGenerics()
			let sig = try require(popNode(kind: .dependentGenericSignature))
			try require(substitutions.count == 1)
			let subsNode = SwiftSymbol(kind: .implPatternSubstitutions, children: [sig, substitutions[0]] + (conformances.isEmpty ? [] : [SwiftSymbol(kind: .typeList, children: conformances)]))
			typeChildren.append(subsNode)
		}
		
		if scanner.conditional(scalar: "I") {
			let (substitutions, conformances) = try demangleBoundGenerics()
			try require(substitutions.count == 1)
			let subsNode = SwiftSymbol(kind: .implInvocationSubstitutions, children: [substitutions[0]] + (conformances.isEmpty ? [] : [SwiftSymbol(kind: .typeList, children: conformances)]))
			typeChildren.append(subsNode)
		}
		
		var genSig = popNode(kind: .dependentGenericSignature)
		if let g = genSig, scanner.conditional(scalar: "P") {
			genSig = g.changeKind(.dependentPseudogenericSignature)
		}
		
		if scanner.conditional(scalar: "e") {
			typeChildren.append(SwiftSymbol(kind: .implEscaping))
		}
		
		if scanner.conditional(scalar: "A") {
			typeChildren.append(SwiftSymbol(kind: .implErasedIsolation))
		}
		
		if scanner.conditional(scalar: "N") {
			typeChildren.append(SwiftSymbol(kind: .implNonisolatedNonsendingIsolation))
		}
		if scanner.conditional(scalar: "O") {
			typeChildren.append(SwiftSymbol(kind: .implCalledOnceFunction))
		}
		if let peek = scanner.peek(), let differentiability = MangledDifferentiabilityKind(rawValue: peek), differentiability != .nonDifferentiable {
			try scanner.skip()
			typeChildren.append(SwiftSymbol(kind: .implDifferentiabilityKind, contents: .index(UInt64(differentiability.rawValue))))
		}
		
		let cAttr: String
		switch try scanner.readScalar() {
		case "y": cAttr = "@callee_unowned"
		case "g": cAttr = "@callee_guaranteed"
		case "x": cAttr = "@callee_owned"
		case "t": cAttr = "@convention(thin)"
		default: throw failure
		}
		typeChildren.append(SwiftSymbol(kind: .implConvention, contents: .name(cAttr)))
		
		let fConv: String?
		var hasClangType = false
		switch try scanner.readScalar() {
		case "B": fConv = "block"
		case "C": fConv = "c"
		case "z":
			if scanner.conditional(scalar: "B") {
				hasClangType = true
				fConv = "block"
			} else if scanner.conditional(scalar: "C") {
				hasClangType = true
				fConv = "c"
			} else {
				try scanner.backtrack()
				fConv = nil
			}
		case "M": fConv = "method"
		case "O": fConv = "objc_method"
		case "K": fConv = "closure"
		case "W": fConv = "witness_method"
		case "V": fConv = "com_method"
		default:
			try scanner.backtrack()
			fConv = nil
		}
		if let fConv {
			var node = SwiftSymbol(kind: .implFunctionConvention, child: SwiftSymbol(kind: .implFunctionConventionName, contents: .name(fConv)))
			if hasClangType {
				try node.children.append(demangleClangType())
			}
			typeChildren.append(node)
		}
		
		if scanner.conditional(scalar: "A") {
			typeChildren.append(SwiftSymbol(kind: .implCoroutineKind, contents: .name("yield_once")))
		} else if scanner.conditional(scalar: "I") {
			typeChildren.append(SwiftSymbol(kind: .implCoroutineKind, contents: .name("yield_once_2")))
		} else if scanner.conditional(scalar: "G") {
			typeChildren.append(SwiftSymbol(kind: .implCoroutineKind, contents: .name("yield_many")))
		}
		
		if scanner.conditional(scalar: "h") {
			typeChildren.append(SwiftSymbol(kind: .implFunctionAttribute, contents: .name("@Sendable")))
		}
		
		if scanner.conditional(scalar: "H") {
			typeChildren.append(SwiftSymbol(kind: .implFunctionAttribute, contents: .name("@async")))
		}
		
		if scanner.conditional(scalar: "T") {
			typeChildren.append(SwiftSymbol(kind: .implSendingResult))
		}
		
		if let g = genSig {
			typeChildren.append(g)
		}
		
		var numTypesToAdd = 0
		while var param = try demangleImplParamConvention(kind: .implParameter) {
			param.children.append(demangleImplParameterResultDifferentiability())
			if let diff = demangleImplParameterSending() {
				param.children.append(diff)
			}
			if let isolated = demangleImplParameterIsolated() {
				param.children.append(isolated)
			}
			if let implicitLeading = demangleImplParameterImplicitLeading() {
				param.children.append(implicitLeading)
			}
			typeChildren.append(param)
			numTypesToAdd += 1
		}
		while var result = try demangleImplResultConvention(kind: .implResult) {
			result.children.append(demangleImplParameterResultDifferentiability())
			typeChildren.append(result)
			numTypesToAdd += 1
		}
		while scanner.conditional(scalar: "Y") {
			typeChildren.append(try require(demangleImplParamConvention(kind: .implYield)))
			numTypesToAdd += 1
		}
		if scanner.conditional(scalar: "z") {
			typeChildren.append(try require(demangleImplResultConvention(kind: .implErrorResult)))
			numTypesToAdd += 1
		}
		try scanner.match(scalar: "_")
		for i in 0..<numTypesToAdd {
			try require(typeChildren.indices.contains(typeChildren.count - i - 1))
			typeChildren[typeChildren.count - i - 1].children.append(try require(popNode(kind: .type)))
		}
		
		return SwiftSymbol(typeWithChildKind: .implFunctionType, childChildren: typeChildren)
	}
	
	mutating func demangleMetatype() throws -> SwiftSymbol {
		switch try scanner.readScalar() {
		case "a": return SwiftSymbol(kind: .typeMetadataAccessFunction, child: try require(popNode(kind: .type)))
		case "A": return SwiftSymbol(kind: .reflectionMetadataAssocTypeDescriptor, child: try popProtocolConformance())
		case "b": return SwiftSymbol(kind: .canonicalSpecializedGenericTypeMetadataAccessFunction, child: try require(popNode(kind: .type)))
		case "B": return SwiftSymbol(kind: .reflectionMetadataBuiltinDescriptor, child: try require(popNode(kind: .type)))
		case "c": return SwiftSymbol(kind: .protocolConformanceDescriptor, child: try require(popProtocolConformance()))
		case "C":
			let t = try require(popNode(kind: .type))
			try require(t.children.first?.kind.isAnyGeneric == true)
			return SwiftSymbol(kind: .reflectionMetadataSuperclassDescriptor, child: try require(t.children.first))
		case "D": return SwiftSymbol(kind: .typeMetadataDemanglingCache, child: try require(popNode(kind: .type)))
		case "f": return SwiftSymbol(kind: .fullTypeMetadata, child: try require(popNode(kind: .type)))
		case "F": return SwiftSymbol(kind: .reflectionMetadataFieldDescriptor, child: try require(popNode(kind: .type)))
		case "g": return SwiftSymbol(kind: .opaqueTypeDescriptorAccessor, child: try require(popNode()))
		case "h": return SwiftSymbol(kind: .opaqueTypeDescriptorAccessorImpl, child: try require(popNode()))
		case "i": return SwiftSymbol(kind: .typeMetadataInstantiationFunction, child: try require(popNode(kind: .type)))
		case "I": return SwiftSymbol(kind: .typeMetadataInstantiationCache, child: try require(popNode(kind: .type)))
		case "j": return SwiftSymbol(kind: .opaqueTypeDescriptorAccessorKey, child: try require(popNode()))
		case "J": return SwiftSymbol(kind: .noncanonicalSpecializedGenericTypeMetadataCache, child: try require(popNode()))
		case "k": return SwiftSymbol(kind: .opaqueTypeDescriptorAccessorVar, child: try require(popNode()))
		case "K": return SwiftSymbol(kind: .metadataInstantiationCache, child: try require(popNode()))
		case "l": return SwiftSymbol(kind: .typeMetadataSingletonInitializationCache, child: try require(popNode(kind: .type)))
		case "L": return SwiftSymbol(kind: .typeMetadataLazyCache, child: try require(popNode(kind: .type)))
		case "m": return SwiftSymbol(kind: .metaclass, child: try require(popNode(kind: .type)))
		case "M": return SwiftSymbol(kind: .canonicalSpecializedGenericMetaclass, child: try require(popNode(kind: .type)))
		case "n": return SwiftSymbol(kind: .nominalTypeDescriptor, child: try require(popNode(kind: .type)))
		case "N": return SwiftSymbol(kind: .noncanonicalSpecializedGenericTypeMetadata, child: try require(popNode(kind: .type)))
		case "o": return SwiftSymbol(kind: .classMetadataBaseOffset, child: try require(popNode(kind: .type)))
		case "p": return SwiftSymbol(kind: .protocolDescriptor, child: try popProtocol())
		case "P": return SwiftSymbol(kind: .genericTypeMetadataPattern, child: try require(popNode(kind: .type)))
		case "q": return SwiftSymbol(kind: .uniquable, child: try require(popNode()))
		case "Q": return SwiftSymbol(kind: .opaqueTypeDescriptor, child: try require(popNode()))
		case "r": return SwiftSymbol(kind: .typeMetadataCompletionFunction, child: try require(popNode(kind: .type)))
		case "s": return SwiftSymbol(kind: .objCResilientClassStub, child: try require(popNode(kind: .type)))
		case "S": return SwiftSymbol(kind: .protocolSelfConformanceDescriptor, child: try require(popNode(kind: .type)))
		case "t": return SwiftSymbol(kind: .fullObjCResilientClassStub, child: try require(popNode(kind: .type)))
		case "u": return SwiftSymbol(kind: .methodLookupFunction, child: try require(popNode(kind: .type)))
		case "U": return SwiftSymbol(kind: .objCMetadataUpdateFunction, child: try require(popNode(kind: .type)))
		case "V": return SwiftSymbol(kind: .propertyDescriptor, child: try require(popNode { $0.isEntity }))
		case "X": return try demanglePrivateContextDescriptor()
		case "z": return SwiftSymbol(kind: .canonicalPrespecializedGenericTypeCachingOnceToken, child: try require(popNode(kind: .type)))
		default: throw failure
		}
	}
	
	mutating func demanglePrivateContextDescriptor() throws -> SwiftSymbol {
		switch try scanner.readScalar() {
		case "E": return SwiftSymbol(kind: .extensionDescriptor, child: try popContext())
		case "M": return SwiftSymbol(kind: .moduleDescriptor, child: try require(popModule()))
		case "Y":
			let discriminator = try require(popNode())
			let context = try popContext()
			return SwiftSymbol(kind: .anonymousDescriptor, children: [context, discriminator])
		case "X": return SwiftSymbol(kind: .anonymousDescriptor, child: try popContext())
		case "A":
			let path = try require(popAssocTypePath())
			let base = try require(popNode(kind: .type))
			return SwiftSymbol(kind: .associatedTypeGenericParamRef, children: [base, path])
		default: throw failure
		}
	}
	
	mutating func demangleArchetype() throws -> SwiftSymbol {
		switch try scanner.readScalar() {
		case "a":
			let ident = try require(popNode(kind: .identifier))
			let arch = try popTypeAndGetChild()
			let assoc = SwiftSymbol(typeWithChildKind: .associatedTypeRef, childChildren: [arch, ident])
			substitutions.append(assoc)
			return assoc
		case "O":
			return SwiftSymbol(kind: .opaqueReturnTypeOf, child: try popContext())
		case "o":
			let index = try demangleIndex()
			let (boundGenericArgs, retroactiveConformances) = try demangleBoundGenerics()
			let name = try require(popNode())
			var opaque = SwiftSymbol(
				kind: .opaqueType,
				children: [
					name,
					SwiftSymbol(kind: .index, contents: .index(index)),
					SwiftSymbol(kind: .typeList, children: boundGenericArgs.reversed())
				]
			)
			if !retroactiveConformances.isEmpty {
				opaque.children.append(SwiftSymbol(kind: .typeList, children: retroactiveConformances))
			}
			let opaqueType = SwiftSymbol(kind: .type, child: opaque)
			substitutions.append(opaqueType)
			return opaqueType
		case "r":
			return SwiftSymbol(typeWithChildKind: .opaqueReturnType, childChildren: [])
		case "R":
			return SwiftSymbol(typeWithChildKind: .opaqueReturnType, childChild: SwiftSymbol(kind: .opaqueReturnTypeIndex, contents: .index(try demangleIndex())))
		case "x":
			let t = try demangleAssociatedTypeSimple(index: nil)
			substitutions.append(t)
			return t
		case "X":
			let t = try demangleAssociatedTypeCompound(index: nil)
			substitutions.append(t)
			return t
		case "y":
			let t = try demangleAssociatedTypeSimple(index: demangleGenericParamIndex())
			substitutions.append(t)
			return t
		case "Y":
			let t = try demangleAssociatedTypeCompound(index: demangleGenericParamIndex())
			substitutions.append(t)
			return t
		case "z":
			let t = try demangleAssociatedTypeSimple(index: getDependentGenericParamType(depth: 0, index: 0))
			substitutions.append(t)
			return t
		case "Z":
			let t = try demangleAssociatedTypeCompound(index: getDependentGenericParamType(depth: 0, index: 0))
			substitutions.append(t)
			return t
		case "p":
			let count = try popTypeAndGetChild()
			let pattern = try popTypeAndGetChild()
			return SwiftSymbol(kind: .type, child: SwiftSymbol(kind: .packExpansion, children: [pattern, count]))
		case "e":
			let pack = try popTypeAndGetChild()
			let level = try demangleIndex()
			return SwiftSymbol(kind: .type, child: SwiftSymbol(kind: .packElement, children: [pack, SwiftSymbol(kind: .packElementLevel, contents: .index(level))]))
		case "P":
			return try popPack()
		case "S":
			return try popSILPack()
		default: throw failure
		}
	}
	
	mutating func demangleAssociatedTypeSimple(index: SwiftSymbol?) throws -> SwiftSymbol {
		let atName = try popAssocTypeName()
		let gpi = try index.map { SwiftSymbol(kind: .type, child: $0) } ?? require(popNode(kind: .type))
		return SwiftSymbol(typeWithChildKind: .dependentMemberType, childChildren: [gpi, atName])
	}
	
	mutating func demangleAssociatedTypeCompound(index: SwiftSymbol?) throws -> SwiftSymbol {
		var assocTypeNames = [SwiftSymbol]()
		var firstElem = false
		repeat {
			firstElem = popNode(kind: .firstElementMarker) != nil
			assocTypeNames.append(try popAssocTypeName())
		} while !firstElem
		
		var base = try index.map { SwiftSymbol(kind: .type, child: $0) } ?? require(popNode(kind: .type))
		while let assocType = assocTypeNames.popLast() {
			base = SwiftSymbol(kind: .type, child: SwiftSymbol(kind: .dependentMemberType, children: [base, assocType]))
		}
		return base
	}
	
	mutating func demangleGenericParamIndex() throws -> SwiftSymbol {
		switch try scanner.readScalar() {
		case "d":
			let depth = try demangleIndex() + 1
			let index = try demangleIndex()
			return try getDependentGenericParamType(depth: Int(depth), index: Int(index))
		case "z":
			return try getDependentGenericParamType(depth: 0, index: 0)
		case "s":
			return SwiftSymbol(kind: .constrainedExistentialSelf)
		default:
			try scanner.backtrack()
			return try getDependentGenericParamType(depth: 0, index: Int(demangleIndex() + 1))
		}
	}
	
	mutating func popAssociatedConformanceWitnessAccessorSubject() throws -> SwiftSymbol {
		if let type = popNode(kind: .type) {
			if type.children.first?.kind == .dependentGenericParamType { return type }
			nodeStack.append(type)
		}
		return try popAssocTypePath()
	}

	mutating func demangleThunkOrSpecialization() throws -> SwiftSymbol {
		let c = try scanner.readScalar()
		switch c {
		case "T":
			switch try scanner.readScalar() {
			case "I": return try SwiftSymbol(kind: .silThunkIdentity, child: require(popNode(where: { $0.isEntity })))
			case "H": return try SwiftSymbol(kind: .silThunkHopToMainActorIfNeeded, child: require(popNode(where: { $0.isEntity })))
			default: throw failure
			}
		case "c": return SwiftSymbol(kind: .curryThunk, child: try require(popNode(where: { $0.isEntity })))
		case "j": return SwiftSymbol(kind: .dispatchThunk, child: try require(popNode(where: { $0.isEntity })))
		case "q": return SwiftSymbol(kind: .methodDescriptor, child: try require(popNode(where: { $0.isEntity })))
		case "o": return SwiftSymbol(kind: .objCAttribute)
		case "O": return SwiftSymbol(kind: .nonObjCAttribute)
		case "D": return SwiftSymbol(kind: .dynamicAttribute)
		case "d": return SwiftSymbol(kind: .directMethodReferenceAttribute)
		case "E": return SwiftSymbol(kind: .distributedThunk)
		case "F": return SwiftSymbol(kind: .distributedAccessor)
		case "a": return SwiftSymbol(kind: .partialApplyObjCForwarder)
		case "A": return SwiftSymbol(kind: .partialApplyForwarder)
		case "m": return SwiftSymbol(kind: .mergedFunction)
		case "X": return SwiftSymbol(kind: .dynamicallyReplaceableFunctionVar)
		case "x": return SwiftSymbol(kind: .dynamicallyReplaceableFunctionKey)
		case "I": return SwiftSymbol(kind: .dynamicallyReplaceableFunctionImpl)
		case "Y": return SwiftSymbol(kind: .asyncSuspendResumePartialFunction, child: try demangleIndexAsNode())
		case "Q": return SwiftSymbol(kind: .asyncAwaitResumePartialFunction, child: try demangleIndexAsNode())
		case "C": return SwiftSymbol(kind: .coroutineContinuationPrototype, child: try require(popNode(kind: .type)))
		case "z": fallthrough
		case "Z":
			let flagMode = try demangleIndexAsNode()
			let sig = popNode(kind: .dependentGenericSignature)
			let resultType = try require(popNode(kind: .type))
			let implType = try require(popNode(kind: .type))
			var node = SwiftSymbol(kind: c == "z" ? .objCAsyncCompletionHandlerImpl : .checkedObjCAsyncCompletionHandlerImpl, children: [implType, resultType, flagMode])
			if let sig {
				node.children.append(sig)
			}
			return node
		case "V":
			let base = try require(popNode(where: { $0.isEntity }))
			let derived = try require(popNode(where: { $0.isEntity }))
			return SwiftSymbol(kind: .vTableThunk, children: [derived, base])
		case "W":
			let entity = try require(popNode(where: { $0.isEntity }))
			let conf = try popProtocolConformance()
			return SwiftSymbol(kind: .protocolWitness, children: [conf, entity])
		case "S":
			return try SwiftSymbol(kind: .protocolSelfConformanceWitness, child: require(popNode(where: { $0.isEntity })))
		case "R", "r", "y":
			let kind = switch c {
			case "R": SwiftSymbol.Kind.reabstractionThunkHelper
			case "y": SwiftSymbol.Kind.reabstractionThunkHelperWithSelf
			default: SwiftSymbol.Kind.reabstractionThunk
			}
			var name = SwiftSymbol(kind: kind)
			if let genSig = popNode(kind: .dependentGenericSignature) {
				name.children.append(genSig)
			}
			if kind == .reabstractionThunkHelperWithSelf {
				name.children.append(try require(popNode(kind: .type)))
			}
			name.children.append(try require(popNode(kind: .type)))
			name.children.append(try require(popNode(kind: .type)))
			return name
		case "g": return try demangleGenericSpecialization(kind: .genericSpecialization)
		case "G": return try demangleGenericSpecialization(kind: .genericSpecializationNotReAbstracted)
		case "B": return try demangleGenericSpecialization(kind: .genericSpecializationInResilienceDomain)
		case "t": return try demangleGenericSpecializationWithDroppedArguments()
		case "s": return try demangleGenericSpecialization(kind: .genericSpecializationPrespecialized)
		case "i": return try demangleGenericSpecialization(kind: .inlinedGenericFunction)
		case "P", "p":
			var spec = try demangleSpecAttributes(kind: c == "P" ? .genericPartialSpecializationNotReAbstracted : .genericPartialSpecialization)
			let param = SwiftSymbol(kind: .genericSpecializationParam, child: try require(popNode(kind: .type)))
			spec.children.append(param)
			return spec
		case "f": return try demangleFunctionSpecialization()
		case "K", "k":
			let nodeKind: SwiftSymbol.Kind
			if scanner.conditional(string: "mu") {
				nodeKind = .keyPathUnappliedMethodThunkHelper
			} else if scanner.conditional(string: "MA") {
				nodeKind = .keyPathAppliedMethodThunkHelper
			} else {
				nodeKind = c == "K" ? .keyPathGetterThunkHelper : .keyPathSetterThunkHelper
			}
			let isSerialized = scanner.conditional(string: "q")
			var types = [SwiftSymbol]()
			var node = popNode(kind: .type)
			while let n = node {
				types.append(n)
				node = popNode(kind: .type)
			}
			var result: SwiftSymbol
			if let n = popNode() {
				if n.kind == .dependentGenericSignature {
					let decl = try require(popNode())
					result = SwiftSymbol(kind: nodeKind, children: [decl, n])
				} else {
					result = SwiftSymbol(kind: nodeKind, child: n)
				}
			} else {
				throw failure
			}
			for t in types {
				result.children.append(t)
			}
			if isSerialized {
				result.children.append(SwiftSymbol(kind: .isSerialized))
			}
			return result
		case "l": return SwiftSymbol(kind: .associatedTypeDescriptor, child: try require(popAssocTypeName()))
		case "L": return SwiftSymbol(kind: .protocolRequirementsBaseDescriptor, child: try require(popProtocol()))
		case "M": return SwiftSymbol(kind: .defaultAssociatedTypeMetadataAccessor, child: try require(popAssocTypeName()))
		case "n":
			let requirement = try popProtocol()
			let associatedTypePath = try popAssociatedConformanceWitnessAccessorSubject()
			let protocolType = try require(popNode(kind: .type))
			return SwiftSymbol(kind: .associatedConformanceDescriptor, children: [protocolType, associatedTypePath, requirement])
		case "N":
			let requirement = try popProtocol()
			let associatedTypePath = try popAssociatedConformanceWitnessAccessorSubject()
			let protocolType = try require(popNode(kind: .type))
			return SwiftSymbol(kind: .defaultAssociatedConformanceAccessor, children: [protocolType, associatedTypePath, requirement])
		case "b":
			let requirement = try popProtocol()
			let protocolType = try require(popNode(kind: .type))
			return SwiftSymbol(kind: .baseConformanceDescriptor, children: [protocolType, requirement])
		case "H", "h":
			let nodeKind: SwiftSymbol.Kind = c == "H" ? .keyPathEqualsThunkHelper : .keyPathHashThunkHelper
			let isSerialized = scanner.peek() == "q"
			var types = [SwiftSymbol]()
			let node = try require(popNode())
			var genericSig: SwiftSymbol? = nil
			if node.kind == .dependentGenericSignature {
				genericSig = node
			} else if node.kind == .type {
				types.append(node)
			} else {
				throw failure
			}
			while let n = popNode() {
				try require(n.kind == .type)
				types.append(n)
			}
			var result = SwiftSymbol(kind: nodeKind)
			for t in types {
				result.children.append(t)
			}
			if let gs = genericSig {
				result.children.append(gs)
			}
			if isSerialized {
				result.children.append(SwiftSymbol(kind: .isSerialized))
			}
			return result
		case "v":
			let index = try demangleIndex()
			if scanner.conditional(scalar: "r") {
				return SwiftSymbol(kind: .outlinedReadOnlyObject, contents: .index(index))
			} else {
				return SwiftSymbol(kind: .outlinedVariable, contents: .index(index))
			}
		case "e":
			let parameters = try demangleBridgedMethodParams()
			try require(!parameters.isEmpty)
			return SwiftSymbol(kind: .outlinedBridgedMethod, contents: .name(parameters))
		case "u": return SwiftSymbol(kind: .asyncFunctionPointer)
		case "U":
			let globalActor = try require(popNode(kind: .type))
			let reabstraction = try require(popNode())
			return SwiftSymbol(kind: .reabstractionThunkHelperWithGlobalActor, children: [reabstraction, globalActor])
		case "J":
			switch try scanner.readScalar() {
			case "S": return try demangleAutoDiffSubsetParametersThunk()
			case "O": return try demangleAutoDiffSelfReorderingReabstractionThunk()
			case "V": return try demangleAutoDiffFunctionOrSimpleThunk(kind: .autoDiffDerivativeVTableThunk)
			default:
				try scanner.backtrack()
				return try demangleAutoDiffFunctionOrSimpleThunk(kind: .autoDiffFunction)
			}
		case "w":
			switch try scanner.readScalar() {
			case "b": return SwiftSymbol(kind: .backDeploymentThunk)
			case "B": return SwiftSymbol(kind: .backDeploymentFallback)
			case "c": return SwiftSymbol(kind: .coroFunctionPointer)
			case "d": return SwiftSymbol(kind: .defaultOverride)
			case "S": return SwiftSymbol(kind: .hasSymbolQuery)
			default: throw failure
			}
		default: throw failure
		}
	}
	
	mutating func demangleAutoDiffFunctionOrSimpleThunk(kind: SwiftSymbol.Kind) throws -> SwiftSymbol {
		var result = SwiftSymbol(kind: kind)
		while let node = popNode() {
			result.children.append(node)
		}
		result.children.reverse()
		let kind = try demangleAutoDiffFunctionKind()
		result.children.append(kind)
		result.children.append(try require(demangleIndexSubset()))
		try scanner.match(scalar: "p")
		result.children.append(try require(demangleIndexSubset()))
		try scanner.match(scalar: "r")
		return result
	}
	
	mutating func demangleAutoDiffFunctionKind() throws -> SwiftSymbol {
		let kind = try scanner.readScalar()
		guard let autoDiffFunctionKind = AutoDiffFunctionKind(UInt64(kind.value)) else {
			throw failure
		}
		return SwiftSymbol(kind: .autoDiffFunctionKind, contents: .index(UInt64(autoDiffFunctionKind.rawValue.value)))
	}
	
	mutating func demangleAutoDiffSubsetParametersThunk() throws -> SwiftSymbol {
		var result = SwiftSymbol(kind: .autoDiffSubsetParametersThunk)
		while let node = popNode() {
			result.children.append(node)
		}
		result.children.reverse()
		let kind = try demangleAutoDiffFunctionKind()
		result.children.append(kind)
		result.children.append(try require(demangleIndexSubset()))
		try scanner.match(scalar: "p")
		result.children.append(try require(demangleIndexSubset()))
		try scanner.match(scalar: "r")
		result.children.append(try require(demangleIndexSubset()))
		try scanner.match(scalar: "P")
		return result
	}
	
	mutating func demangleAutoDiffSelfReorderingReabstractionThunk() throws -> SwiftSymbol {
		var result = SwiftSymbol(kind: .autoDiffSelfReorderingReabstractionThunk)
		if let dependentGenericSignature = popNode(kind: .dependentGenericSignature) {
			result.children.append(dependentGenericSignature)
		}
		result.children.append(try require(popNode(kind: .type)))
		result.children.append(try require(popNode(kind: .type)))
		result.children.reverse()
		result.children.append(try demangleAutoDiffFunctionKind())
		return result
	}
	
	mutating func demangleDifferentiabilityWitness() throws -> SwiftSymbol {
		var result = SwiftSymbol(kind: .differentiabilityWitness)
		let optionalGenSig = popNode(kind: .dependentGenericSignature)
		while let node = popNode() {
			result.children.append(node)
		}
		result.children.reverse()
		let kind: MangledDifferentiabilityKind = switch try scanner.readScalar() {
		case "f": .forward
		case "r": .reverse
		case "d": .normal
		case "l": .linear
		default: throw failure
		}
		result.children.append(SwiftSymbol(kind: .index, contents: .index(UInt64(kind.rawValue.value))))
		result.children.append(try require(demangleIndexSubset()))
		try scanner.match(scalar: "p")
		result.children.append(try require(demangleIndexSubset()))
		try scanner.match(scalar: "r")
		if let optionalGenSig {
			result.children.append(optionalGenSig)
		}
		return result
	}
	
	mutating func demangleIndexSubset() throws -> SwiftSymbol {
		var str = ""
		while let c = scanner.conditional(where: { $0 == "S" || $0 == "U" }) {
			str.unicodeScalars.append(c)
		}
		try require(!str.isEmpty)
		return SwiftSymbol(kind: .indexSubset, contents: .name(str))
	}
	
	mutating func demangleDifferentiableFunctionType() throws -> SwiftSymbol {
		let kind: MangledDifferentiabilityKind = switch try scanner.readScalar() {
		case "f": .forward
		case "r": .reverse
		case "d": .normal
		case "l": .linear
		default: throw failure
		}
		return SwiftSymbol(kind: .differentiableFunctionType, contents: .index(UInt64(kind.rawValue.value)))
		
	}
	
	mutating func demangleBridgedMethodParams() throws -> String {
		if scanner.conditional(scalar: "_") {
			return ""
		}
		var str = ""
		let kind = try scanner.readScalar()
		switch kind {
		case "o", "p", "a", "m": str.unicodeScalars.append(kind)
		default: return ""
		}
		while !scanner.conditional(scalar: "_") {
			let c = try scanner.readScalar()
			try require(c == "n" || c == "b" || c == "g")
			str.unicodeScalars.append(c)
		}
		return str
	}
	
	mutating func demangleGenericSpecialization(kind: SwiftSymbol.Kind, droppedArguments: SwiftSymbol? = nil) throws -> SwiftSymbol {
		var spec = try demangleSpecAttributes(kind: kind)
		if let droppedArguments {
			spec.children.append(contentsOf: droppedArguments.children)
		}
		let list = try popTypeList()
		for t in list.children {
			spec.children.append(SwiftSymbol(kind: .genericSpecializationParam, child: t))
		}
		return spec
	}
	
	mutating func demangleGenericSpecializationWithDroppedArguments() throws -> SwiftSymbol {
		try scanner.backtrack()
		var tmp = SwiftSymbol(kind: .genericSpecialization)
		while scanner.conditional(scalar: "t") {
			let n = try demangleNatural().map { SwiftSymbol.Contents.index($0 + 1) } ?? SwiftSymbol.Contents.index(0)
			tmp.children.append(SwiftSymbol(kind: .droppedArgument, contents: n))
		}
		let kind: SwiftSymbol.Kind = switch try scanner.readScalar() {
		case "g": .genericSpecialization
		case "G": .genericSpecializationNotReAbstracted
		case "B": .genericSpecializationInResilienceDomain
		default: throw failure
		}
		return try demangleGenericSpecialization(kind: kind, droppedArguments: tmp)
	}
	
	mutating func demangleFunctionSpecialization() throws -> SwiftSymbol {
		var spec = try demangleSpecAttributes(kind: .functionSignatureSpecialization)
		if spec.children.first?.kind == .representationChanged { return spec }
		var paramIdx: UInt64 = 0
		while !scanner.conditional(scalar: "_") {
			spec.children.append(try demangleFuncSpecParam(kind: .functionSignatureSpecializationParam))
			paramIdx += 1
		}
		if !scanner.conditional(scalar: "n") {
			spec.children.append(try demangleFuncSpecParam(kind: .functionSignatureSpecializationReturn))
		}
		
		for parameterIndex in spec.children.indices.reversed() {
			var parameter = spec.children[parameterIndex]
			guard parameter.kind == .functionSignatureSpecializationParam else { continue }
			let fixedChildren = parameter.children.count
			var arguments: [SwiftSymbol] = []
			for child in parameter.children.reversed() {
				guard child.kind == .functionSignatureSpecializationParamKind,
					let value = child.index, let kind = FunctionSigSpecializationParamKind(rawValue: value) else { continue }
				switch kind {
				case .closureProp, .escapingClosureProp:
					while let type = popNode(kind: .type) { arguments.append(type) }
				case .constantPropKeyPath:
					arguments.append(try require(popNode(kind: .type)))
					arguments.append(try require(popNode(kind: .type)))
				case .constantPropStruct:
					arguments.append(try require(popNode(kind: .type)))
					continue
				case .constantPropFunction, .constantPropGlobal, .constantPropString: break
				default: continue
				}
				arguments.append(try require(popNode(kind: .identifier)))
			}
			parameter.children.insert(contentsOf: arguments.reversed(), at: fixedChildren)
			spec.children[parameterIndex] = parameter
		}
		return spec
	}
	
	mutating func demangleFuncSpecParam(kind: SwiftSymbol.Kind) throws -> SwiftSymbol {
		var param = SwiftSymbol(kind: kind)
		switch try scanner.readScalar() {
		case "n": break
		case "c": param.children.append(SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.closureProp.rawValue)))
		case "E": param.children.append(SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.escapingClosureProp.rawValue)))
		case "C":
			param.children.append(SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.closurePropPreviousArg.rawValue)))
			param.children.append(SwiftSymbol(kind: .functionSignatureSpecializationParamPayload, contents: .index(try require(demangleNatural()))))
		case "p":
			while true {
				if scanner.isAtEnd { return param }
				let parameterKind = try scanner.readScalar()
				switch parameterKind {
				case "S": param.children.append(SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.constantPropStruct.rawValue)))
				case "f": param.children.append(SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.constantPropFunction.rawValue)))
				case "g": param.children.append(SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.constantPropGlobal.rawValue)))
				case "i", "d":
					let numericKind: FunctionSigSpecializationParamKind = parameterKind == "i" ? .constantPropInteger : .constantPropFloat
					param.children.append(SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(numericKind.rawValue)))
					var payload = ""
					while let digit = scanner.conditional(where: { $0.isDigit }) {
						payload.unicodeScalars.append(digit)
					}
					try require(!payload.isEmpty)
					param.children.append(SwiftSymbol(kind: .functionSignatureSpecializationParamPayload, contents: .name(payload)))
				case "s":
					let encoding: String
					switch try scanner.readScalar() {
					case "b": encoding = "u8"
					case "w": encoding = "u16"
					case "c": encoding = "objc"
					default: throw failure
					}
					param.children.append(SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.constantPropString.rawValue)))
					param.children.append(SwiftSymbol(kind: .functionSignatureSpecializationParamPayload, contents: .name(encoding)))
				case "k":
					param.children.append(SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.constantPropKeyPath.rawValue)))
				default:
					try scanner.backtrack()
					return param
				}
			}
		case "e":
			var value = FunctionSigSpecializationParamKind.existentialToGeneric.rawValue
			if scanner.conditional(scalar: "D") {
				value |= FunctionSigSpecializationParamKind.dead.rawValue
			}
			if scanner.conditional(scalar: "G") {
				value |= FunctionSigSpecializationParamKind.ownedToGuaranteed.rawValue
			}
			if scanner.conditional(scalar: "O") {
				value |= FunctionSigSpecializationParamKind.guaranteedToOwned.rawValue
			}
			if scanner.conditional(scalar: "X") {
				value |= FunctionSigSpecializationParamKind.sroa.rawValue
			}
			param.children.append(SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(value)))
		case "d":
			var value = FunctionSigSpecializationParamKind.dead.rawValue
			if scanner.conditional(scalar: "G") {
				value |= FunctionSigSpecializationParamKind.ownedToGuaranteed.rawValue
			}
			if scanner.conditional(scalar: "O") {
				value |= FunctionSigSpecializationParamKind.guaranteedToOwned.rawValue
			}
			if scanner.conditional(scalar: "X") {
				value |= FunctionSigSpecializationParamKind.sroa.rawValue
			}
			param.children.append(SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(value)))
		case "g":
			var value = FunctionSigSpecializationParamKind.ownedToGuaranteed.rawValue
			if scanner.conditional(scalar: "O") {
				value |= FunctionSigSpecializationParamKind.guaranteedToOwned.rawValue
			}
			if scanner.conditional(scalar: "X") {
				value |= FunctionSigSpecializationParamKind.sroa.rawValue
			}
			param.children.append(SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(value)))
		case "o":
			var value = FunctionSigSpecializationParamKind.guaranteedToOwned.rawValue
			if scanner.conditional(scalar: "X") {
				value |= FunctionSigSpecializationParamKind.sroa.rawValue
			}
			param.children.append(SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(value)))
		case "x":
			param.children.append(SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.sroa.rawValue)))
		case "i":
			param.children.append(SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.boxToValue.rawValue)))
		case "s":
			param.children.append(SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.boxToStack.rawValue)))
		case "r":
			param.children.append(SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.inOutToOut.rawValue)))
		default: throw failure
		}
		return param
	}
	
	mutating func addFuncSpecParamNumber(param: inout SwiftSymbol, kind: FunctionSigSpecializationParamKind) throws {
		param.children.append(SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(kind.rawValue)))
		let str = scanner.readWhile { $0.isDigit }
		try require(!str.isEmpty)
		param.children.append(SwiftSymbol(kind: .functionSignatureSpecializationParamPayload, contents: .name(str)))
	}
	
	mutating func demangleSpecAttributes(kind: SwiftSymbol.Kind, demangleUniqueId: Bool = false) throws -> SwiftSymbol {
		let isSerialized = scanner.conditional(scalar: "q")
		let asyncRemoved = scanner.conditional(scalar: "a")
		let representationChanged = scanner.conditional(scalar: "r")
		let passId = Int(try scanner.readScalar().value) - Int(UnicodeScalar("0").value)
		try require((0...9).contains(passId))
		let contents = demangleUniqueId ? (try demangleNatural().map { SwiftSymbol.Contents.index($0) } ?? SwiftSymbol.Contents.none) : SwiftSymbol.Contents.none
		var specName = SwiftSymbol(kind: kind, contents: contents)
		if isSerialized {
			specName.children.append(SwiftSymbol(kind: .isSerialized))
		}
		if asyncRemoved {
			specName.children.append(SwiftSymbol(kind: .asyncRemoved))
		}
		if representationChanged {
			specName.children.append(SwiftSymbol(kind: .representationChanged))
		}
		specName.children.append(SwiftSymbol(kind: .specializationPassID, contents: .index(UInt64(passId))))
		return specName
	}
	
	mutating func demangleWitness() throws -> SwiftSymbol {
		let c = try scanner.readScalar()
		switch c {
		case "C": return SwiftSymbol(kind: .enumCase, child: try require(popNode(where: { $0.isEntity })))
		case "V": return SwiftSymbol(kind: .valueWitnessTable, child: try require(popNode(kind: .type)))
		case "v":
			let directness: UInt64
			switch try scanner.readScalar() {
			case "d": directness = Directness.direct.rawValue
			case "i": directness = Directness.indirect.rawValue
			default: throw failure
			}
			return SwiftSymbol(kind: .fieldOffset, children: [SwiftSymbol(kind: .directness, contents: .index(directness)), try require(popNode(where: { $0.isEntity }))])
		case "S": return SwiftSymbol(kind: .protocolSelfConformanceWitnessTable, child: try popProtocolConformance())
		case "P": return SwiftSymbol(kind: .protocolWitnessTable, child: try popProtocolConformance())
		case "p": return SwiftSymbol(kind: .protocolWitnessTablePattern, child: try popProtocolConformance())
		case "G": return SwiftSymbol(kind: .genericProtocolWitnessTable, child: try popProtocolConformance())
		case "I": return SwiftSymbol(kind: .genericProtocolWitnessTableInstantiationFunction, child: try popProtocolConformance())
		case "r": return SwiftSymbol(kind: .resilientProtocolWitnessTable, child: try popProtocolConformance())
		case "l":
			let conf = try popProtocolConformance()
			let type = try require(popNode(kind: .type))
			return SwiftSymbol(kind: .lazyProtocolWitnessTableAccessor, children: [type, conf])
		case "L":
			let conf = try popProtocolConformance()
			let type = try require(popNode(kind: .type))
			return SwiftSymbol(kind: .lazyProtocolWitnessTableCacheVariable, children: [type, conf])
		case "a": return SwiftSymbol(kind: .protocolWitnessTableAccessor, child: try popProtocolConformance())
		case "t":
			let name = try require(popNode(where: { $0.isDeclName }))
			let conf = try popProtocolConformance()
			return SwiftSymbol(kind: .associatedTypeMetadataAccessor, children: [conf, name])
		case "T":
			let protoType = try require(popNode(kind: .type))
			let assocTypePath = try popAssocTypePath()
			return SwiftSymbol(kind: .associatedTypeWitnessTableAccessor, children: [try popProtocolConformance(), assocTypePath, protoType])
		case "b":
			let protoTy = try require(popNode(kind: .type))
			let conf = try popProtocolConformance()
			return SwiftSymbol(kind: .baseWitnessTableAccessor, children: [conf, protoTy])
		case "O":
			let sig = popNode(kind: .dependentGenericSignature)
			let type = try require(popNode(kind: .type))
			let children: [SwiftSymbol] = sig.map { [type, $0] } ?? [type]
			switch try scanner.readScalar() {
			case "B": return SwiftSymbol(kind: .outlinedInitializeWithTakeNoValueWitness, children: children)
			case "C": return SwiftSymbol(kind: .outlinedInitializeWithCopyNoValueWitness, children: children)
			case "D": return SwiftSymbol(kind: .outlinedAssignWithTakeNoValueWitness, children: children)
			case "F": return SwiftSymbol(kind: .outlinedAssignWithCopyNoValueWitness, children: children)
			case "H": return SwiftSymbol(kind: .outlinedDestroyNoValueWitness, children: children)
			case "y": return SwiftSymbol(kind: .outlinedCopy, children: children)
			case "e": return SwiftSymbol(kind: .outlinedConsume, children: children)
			case "r": return SwiftSymbol(kind: .outlinedRetain, children: children)
			case "s": return SwiftSymbol(kind: .outlinedRelease, children: children)
			case "b": return SwiftSymbol(kind: .outlinedInitializeWithTake, children: children)
			case "c": return SwiftSymbol(kind: .outlinedInitializeWithCopy, children: children)
			case "d": return SwiftSymbol(kind: .outlinedAssignWithTake, children: children)
			case "f": return SwiftSymbol(kind: .outlinedAssignWithCopy, children: children)
			case "h": return SwiftSymbol(kind: .outlinedDestroy, children: children)
			case "g": return SwiftSymbol(kind: .outlinedEnumGetTag, children: children)
			case "i": return SwiftSymbol(kind: .outlinedEnumTagStore, children: children + [try demangleIndexAsNode()])
			case "j": return SwiftSymbol(kind: .outlinedEnumProjectDataForLoad, children: children + [try demangleIndexAsNode()])
			default: throw failure
			}
		case "Z", "z":
			var declList = SwiftSymbol(kind: .globalVariableOnceDeclList)
			while popNode(kind: .firstElementMarker) != nil {
				guard let identifier = popNode(where: { $0.isDeclName }) else { throw failure }
				declList.children.append(identifier)
			}
			declList.children.reverse()
			return SwiftSymbol(kind: c == "Z" ? .globalVariableOnceFunction : .globalVariableOnceToken, children: [try popContext(), declList])
		case "J":
			return try demangleDifferentiabilityWitness()
		default: throw failure
		}
	}
	
	mutating func demangleSpecialType() throws -> SwiftSymbol {
		let specialChar = try scanner.readScalar()
		switch specialChar {
		case "E": return try popFunctionType(kind: .noEscapeFunctionType)
		case "A": return try popFunctionType(kind: .escapingAutoClosureType)
		case "f": return try popFunctionType(kind: .thinFunctionType)
		case "K": return try popFunctionType(kind: .autoClosureType)
		case "U": return try popFunctionType(kind: .uncurriedFunctionType)
		case "L": return try popFunctionType(kind: .escapingObjCBlock)
		case "B": return try popFunctionType(kind: .objCBlock)
		case "O": return try popFunctionType(kind: .calledOnceFunctionType)
		case "y": return try popFunctionParams(kind: .yieldTypes)
		case "C": return try popFunctionType(kind: .cFunctionPointer)
		case "g": fallthrough
		case "G": return try demangleExtendedExistentialShape(nodeKind: specialChar)
		case "j": return try demangleSymbolicExtendedExistentialType()
		case "z":
			switch try scanner.readScalar() {
			case "B": return try popFunctionType(kind: .objCBlock, hasClangType: true)
			case "C": return try popFunctionType(kind: .cFunctionPointer, hasClangType: true)
			default: throw failure
			}
		case "o": return SwiftSymbol(typeWithChildKind: .unowned, childChild: try require(popNode(kind: .type)))
		case "u": return SwiftSymbol(typeWithChildKind: .unmanaged, childChild: try require(popNode(kind: .type)))
		case "w": return SwiftSymbol(typeWithChildKind: .weak, childChild: try require(popNode(kind: .type)))
		case "b": return SwiftSymbol(typeWithChildKind: .silBoxType, childChild: try require(popNode(kind: .type)))
		case "D": return SwiftSymbol(typeWithChildKind: .dynamicSelf, childChild: try require(popNode(kind: .type)))
		case "M":
			let mtr = try demangleMetatypeRepresentation()
			let type = try require(popNode(kind: .type))
			return SwiftSymbol(typeWithChildKind: .metatype, childChildren: [mtr, type])
		case "m":
			let mtr = try demangleMetatypeRepresentation()
			let type = try require(popNode(kind: .type))
			return SwiftSymbol(typeWithChildKind: .existentialMetatype, childChildren: [mtr, type])
		case "P":
			let reqs = try demangleConstrainedExistentialRequirementList()
			let base = try require(popNode(kind: .type))
			return SwiftSymbol(typeWithChildKind: .constrainedExistential, childChildren: [base, reqs])
		case "p": return SwiftSymbol(typeWithChildKind: .existentialMetatype, childChild: try require(popNode(kind: .type)))
		case "c":
			let superclass = try require(popNode(kind: .type))
			let protocols = try demangleProtocolList()
			return SwiftSymbol(typeWithChildKind: .protocolListWithClass, childChildren: [protocols, superclass])
		case "l": return SwiftSymbol(typeWithChildKind: .protocolListWithAnyObject, childChild: try demangleProtocolList())
		case "X", "x":
			var signatureGenericArgs: (SwiftSymbol, SwiftSymbol)? = nil
			if specialChar == "X" {
				signatureGenericArgs = (try require(popNode(kind: .dependentGenericSignature)), try popTypeList())
			}
			
			let fieldTypes = try popTypeList()
			var layout = SwiftSymbol(kind: .silBoxLayout)
			for fieldType in fieldTypes.children {
				try require(fieldType.kind == .type)
				if fieldType.children.first?.kind == .inOut {
					layout.children.append(SwiftSymbol(kind: .silBoxMutableField, child: SwiftSymbol(kind: .type, child: try require(fieldType.children.first?.children.first))))
				} else {
					layout.children.append(SwiftSymbol(kind: .silBoxImmutableField, child: fieldType))
				}
			}
			var boxType = SwiftSymbol(kind: .silBoxTypeWithLayout, child: layout)
			if let (signature, genericArgs) = signatureGenericArgs {
				boxType.children.append(signature)
				boxType.children.append(genericArgs)
			}
			return SwiftSymbol(kind: .type, child: boxType)
		case "Y": return try demangleAnyGenericType(kind: .otherNominalType)
		case "Z":
			let types = try popTypeList()
			let name = try require(popNode(kind: .identifier))
			let parent = try popContext()
			return SwiftSymbol(kind: .anonymousContext, children: [name, parent, types])
		case "e": return SwiftSymbol(kind: .type, child: SwiftSymbol(kind: .errorType))
		case "S":
			switch try scanner.readScalar() {
			case "q": return SwiftSymbol(typeWithChildKind: .sugaredOptional, childChild: try require(popNode(kind: .type)))
			case "a": return SwiftSymbol(typeWithChildKind: .sugaredArray, childChild: try require(popNode(kind: .type)))
			case "D":
				let value = try require(popNode(kind: .type))
				let key = try require(popNode(kind: .type))
				return SwiftSymbol(typeWithChildKind: .sugaredDictionary, childChildren: [key, value])
			case "A":
				let element = try require(popNode(kind: .type))
				let count = try require(popNode(kind: .type))
				return SwiftSymbol(typeWithChildKind: .sugaredInlineArray, childChildren: [count, element])
			case "p": return SwiftSymbol(typeWithChildKind: .sugaredParen, childChild: try require(popNode(kind: .type)))
			default: throw failure
			}
		default: throw failure
		}
	}
	
	mutating func demangleSymbolicExtendedExistentialType() throws -> SwiftSymbol {
		let retroactiveConformances = try popRetroactiveConformances()
		var args = SwiftSymbol(kind: .typeList)
		while let type = popNode(kind: .type) {
			args.children.append(type)
		}
		args.children.reverse()
		let shape = try require(popNode(where: { $0 == .uniqueExtendedExistentialTypeShapeSymbolicReference || $0 == .nonUniqueExtendedExistentialTypeShapeSymbolicReference }))
		if let retroactiveConformances {
			return SwiftSymbol(typeWithChildKind: .symbolicExtendedExistentialType, childChildren: [shape, args, retroactiveConformances])
		} else {
			return SwiftSymbol(typeWithChildKind: .symbolicExtendedExistentialType, childChildren: [shape, args])
		}
	}
	
	mutating func demangleExtendedExistentialShape(nodeKind: UnicodeScalar) throws -> SwiftSymbol {
		let type = try require(popNode(kind: .type))
		var genSig: SwiftSymbol?
		if nodeKind == "G" {
			genSig = popNode(kind: .dependentGenericSignature)
		}
		if let genSig {
			return SwiftSymbol(kind: .extendedExistentialTypeShape, children: [genSig, type])
		} else {
			return SwiftSymbol(kind: .extendedExistentialTypeShape, child: type)
		}
	}
	
	mutating func demangleMetatypeRepresentation() throws -> SwiftSymbol {
		let value: String
		switch try scanner.readScalar() {
		case "t": value = "@thin"
		case "T": value = "@thick"
		case "o": value = "@objc_metatype"
		default: throw failure
		}
		return SwiftSymbol(kind: .metatypeRepresentation, contents: .name(value))
	}
	
	mutating func demangleAccessor(child: SwiftSymbol) throws -> SwiftSymbol {
		let kind: SwiftSymbol.Kind
		switch try scanner.readScalar() {
		case "m": kind = .materializeForSet
		case "s": kind = .setter
		case "g": kind = .getter
		case "G": kind = .globalGetter
		case "w": kind = .willSet
		case "W": kind = .didSet
		case "r": kind = .readAccessor
		case "y": kind = .yieldingBorrowAccessor
		case "M": kind = .modifyAccessor
		case "x": kind = .yieldingMutateAccessor
		case "i": kind = .initAccessor
		case "b": kind = .borrowAccessor
		case "z": kind = .mutateAccessor
		case "a":
			switch try scanner.readScalar() {
			case "O": kind = .owningMutableAddressor
			case "o": kind = .nativeOwningMutableAddressor
			case "P": kind = .nativePinningMutableAddressor
			case "u": kind = .unsafeMutableAddressor
			default: throw failure
			}
		case "l":
			switch try scanner.readScalar() {
			case "O": kind = .owningAddressor
			case "o": kind = .nativeOwningAddressor
			case "p": kind = .nativePinningAddressor
			case "u": kind = .unsafeAddressor
			default: throw failure
			}
		case "p": return child
		default: throw failure
		}
		return SwiftSymbol(kind: kind, child: child)
	}
	
	mutating func demangleFunctionEntity() throws -> SwiftSymbol {
		let argsAndKind: (args: DemangleFunctionEntityArgs, kind: SwiftSymbol.Kind)
		switch try scanner.readScalar() {
		case "D": argsAndKind = (.none, .deallocator)
		case "d": argsAndKind = (.none, .destructor)
		case "Z": argsAndKind = (.none, .isolatedDeallocator)
		case "E": argsAndKind = (.none, .iVarDestroyer)
		case "e": argsAndKind = (.none, .iVarInitializer)
		case "i": argsAndKind = (.none, .initializer)
		case "C": argsAndKind = (.typeAndMaybePrivateName, .allocator)
		case "c": argsAndKind = (.typeAndMaybePrivateName, .constructor)
		case "U": argsAndKind = (.typeAndIndex, .explicitClosure)
		case "u": argsAndKind = (.typeAndIndex, .implicitClosure)
		case "A": argsAndKind = (.index, .defaultArgumentInitializer)
		case "m": return try demangleEntity(kind: .macro)
		case "M": return try demangleMacroExpansion()
		case "p": return try demangleEntity(kind: .genericTypeParamDecl)
		case "F": argsAndKind = (.none, .propertyWrappedFieldInitAccessor)
		case "P": argsAndKind = (.none, .propertyWrapperBackingInitializer)
		case "W": argsAndKind = (.none, .propertyWrapperInitFromProjectedValue)
		default: throw failure
		}
		
		var children = [SwiftSymbol]()
		switch argsAndKind.args {
		case .none: break
		case .index: children.append(try demangleIndexAsNode())
		case .typeAndIndex:
			let index = try demangleIndexAsNode()
			let type = try require(popNode(kind: .type))
			children += [index, type]
		case .typeAndMaybePrivateName:
			let privateName = popNode(kind: .privateDeclName)
			var paramType = try require(popNode(kind: .type))
			let labelList = try popFunctionParamLabels(type: &paramType)
			if let ll = labelList {
				children.append(ll)
				children.append(paramType)
			} else {
				children.append(paramType)
			}
			if let pn = privateName {
				children.append(pn)
			}
		}
		return SwiftSymbol(kind: argsAndKind.kind, children: [try popContext()] + children)
	}
	
	mutating func demangleEntity(kind: SwiftSymbol.Kind) throws -> SwiftSymbol {
		var type = try require(popNode(kind: .type))
		let labelList = try popFunctionParamLabels(type: &type)
		let name = try require(popNode(where: { $0.isDeclName }))
		let context = try popContext()
		let result = if let labelList = labelList {
			SwiftSymbol(kind: kind, children: [context, name, labelList, type])
		} else {
			SwiftSymbol(kind: kind, children: [context, name, type])
		}
		setParentForOpaqueReturnTypeNodes(visited: &type, parentId: getParentID(parent: result, flavor: flavor))
		return result
	}
	
	mutating func demangleVariable() throws -> SwiftSymbol {
		return try demangleAccessor(child: demangleEntity(kind: .variable))
	}
	
	mutating func demangleSubscript() throws -> SwiftSymbol {
		let privateName = popNode(kind: .privateDeclName)
		var type = try require(popNode(kind: .type))
		let labelList = try popFunctionParamLabels(type: &type)
		let context = try popContext()
		
		var ss = SwiftSymbol(kind: .subscript, child: context)
		if let labelList = labelList {
			ss.children.append(labelList)
		}
		setParentForOpaqueReturnTypeNodes(visited: &type, parentId: getParentID(parent: ss, flavor: flavor))
		ss.children.append(type)
		if let pn = privateName {
			ss.children.append(pn)
		}
		return try demangleAccessor(child: ss)
	}
	
	mutating func demangleProtocolList() throws -> SwiftSymbol {
		var typeList = SwiftSymbol(kind: .typeList)
		if popNode(kind: .emptyList) == nil {
			var firstElem = false
			repeat {
				firstElem = popNode(kind: .firstElementMarker) != nil
				typeList.children.insert(try popProtocol(), at: 0)
			} while !firstElem
		}
		return SwiftSymbol(kind: .protocolList, child: typeList)
	}
	
	mutating func demangleProtocolListType() throws -> SwiftSymbol {
		return SwiftSymbol(kind: .type, child: try demangleProtocolList())
	}
	
	mutating func demangleConstrainedExistentialRequirementList() throws -> SwiftSymbol {
		var reqList = SwiftSymbol(kind: .constrainedExistentialRequirementList)
		var firstElement = false
		repeat {
			firstElement = (popNode(kind: .firstElementMarker) != nil)
			let req = try require(popNode(where: { $0.isRequirement }))
			reqList.children.append(req)
		} while !firstElement
		reqList.children.reverse()
		return reqList
	}
	
	mutating func demangleGenericSignature(hasParamCounts: Bool) throws -> SwiftSymbol {
		var sig = SwiftSymbol(kind: .dependentGenericSignature)
		if hasParamCounts {
			while !scanner.conditional(scalar: "l") {
				var count: UInt64 = 0
				if !scanner.conditional(scalar: "z") {
					count = try demangleIndex() + 1
				}
				sig.children.append(SwiftSymbol(kind: .dependentGenericParamCount, contents: .index(count)))
			}
		} else {
			sig.children.append(SwiftSymbol(kind: .dependentGenericParamCount, contents: .index(1)))
		}
		let requirementsIndex = sig.children.endIndex
		while let req = popNode(where: { $0.isRequirement }) {
			sig.children.insert(req, at: requirementsIndex)
		}
		return sig
	}
	
	mutating func demangleGenericRequirement() throws -> SwiftSymbol {
		let constraintAndTypeKinds: (constraint: DemangleGenericRequirementConstraintKind, type: DemangleGenericRequirementTypeKind)
		var inverseKind: SwiftSymbol?
		switch try scanner.readScalar() {
		case "V": constraintAndTypeKinds = (.valueMarker, .generic)
		case "v": constraintAndTypeKinds = (.packMarker, .generic)
		case "c": constraintAndTypeKinds = (.baseClass, .assoc)
		case "C": constraintAndTypeKinds = (.baseClass, .compoundAssoc)
		case "b": constraintAndTypeKinds = (.baseClass, .generic)
		case "B": constraintAndTypeKinds = (.baseClass, .substitution)
		case "t": constraintAndTypeKinds = (.sameType, .assoc)
		case "T": constraintAndTypeKinds = (.sameType, .compoundAssoc)
		case "s": constraintAndTypeKinds = (.sameType, .generic)
		case "S": constraintAndTypeKinds = (.sameType, .substitution)
		case "m": constraintAndTypeKinds = (.layout, .assoc)
		case "M": constraintAndTypeKinds = (.layout, .compoundAssoc)
		case "l": constraintAndTypeKinds = (.layout, .generic)
		case "L": constraintAndTypeKinds = (.layout, .substitution)
		case "p": constraintAndTypeKinds = (.protocol, .assoc)
		case "P": constraintAndTypeKinds = (.protocol, .compoundAssoc)
		case "Q": constraintAndTypeKinds = (.protocol, .substitution)
		case "h": constraintAndTypeKinds = (.sameShape, .generic)
		case "i":
			constraintAndTypeKinds = (.inverse, .generic)
			inverseKind = try demangleIndexAsNode()
		case "j":
			constraintAndTypeKinds = (.inverse, .assoc)
			inverseKind = try demangleIndexAsNode()
		case "J":
			constraintAndTypeKinds = (.inverse, .compoundAssoc)
			inverseKind = try demangleIndexAsNode()
		case "I":
			constraintAndTypeKinds = (.inverse, .substitution)
			inverseKind = try demangleIndexAsNode()
		default:
			constraintAndTypeKinds = (.protocol, .generic)
			try scanner.backtrack()
		}
		
		let constrType: SwiftSymbol
		switch constraintAndTypeKinds.type {
		case .generic: constrType = SwiftSymbol(kind: .type, child: try demangleGenericParamIndex())
		case .assoc:
			constrType = try demangleAssociatedTypeSimple(index: demangleGenericParamIndex())
			substitutions.append(constrType)
		case .compoundAssoc:
			constrType = try demangleAssociatedTypeCompound(index: try demangleGenericParamIndex())
			substitutions.append(constrType)
		case .substitution: constrType = try require(popNode(kind: .type))
		}
		
		switch constraintAndTypeKinds.constraint {
		case .valueMarker: return SwiftSymbol(kind: .dependentGenericParamValueMarker, children: [constrType, try require(popNode(kind: .type))])
		case .packMarker: return SwiftSymbol(kind: .dependentGenericParamPackMarker, children: [constrType])
		case .protocol: return SwiftSymbol(kind: .dependentGenericConformanceRequirement, children: [constrType, try popProtocol()])
		case .inverse: return SwiftSymbol(kind: .dependentGenericInverseConformanceRequirement, children: [constrType, try require(inverseKind)])
		case .baseClass: return SwiftSymbol(kind: .dependentGenericConformanceRequirement, children: [constrType, try require(popNode(kind: .type))])
		case .sameType: return SwiftSymbol(kind: .dependentGenericSameTypeRequirement, children: [constrType, try require(popNode(kind: .type))])
		case .sameShape: return SwiftSymbol(kind: .dependentGenericSameShapeRequirement, children: [constrType, try require(popNode(kind: .type))])
		case .layout:
			let c = try scanner.readScalar()
			var size: SwiftSymbol? = nil
			var alignment: SwiftSymbol? = nil
			switch c {
			case "U", "R", "N", "C", "D", "T", "B": break
			case "E", "M":
				size = try demangleIndexAsNode()
				alignment = try demangleIndexAsNode()
			case "e", "m", "S":
				size = try demangleIndexAsNode()
			default: throw failure
			}
			let name = SwiftSymbol(kind: .identifier, contents: .name(String(String.UnicodeScalarView([c]))))
			var layoutRequirement = SwiftSymbol(kind: .dependentGenericLayoutRequirement, children: [constrType, name])
			if let s = size {
				layoutRequirement.children.append(s)
			}
			if let a = alignment {
				layoutRequirement.children.append(a)
			}
			return layoutRequirement
		}
	}
	
	mutating func demangleGenericType() throws -> SwiftSymbol {
		let genSig = try require(popNode(kind: .dependentGenericSignature))
		let type = try require(popNode(kind: .type))
		return SwiftSymbol(typeWithChildKind: .dependentGenericType, childChildren: [genSig, type])
	}
	
	mutating func demangleValueWitness() throws -> SwiftSymbol {
		let code = try scanner.readScalars(count: 2)
		let kind = try require(ValueWitnessKind(code: code))
		return SwiftSymbol(kind: .valueWitness, children: [SwiftSymbol(kind: .index, contents: .index(kind.rawValue)), try require(popNode(kind: .type))])
	}
}

extension SwiftSymbol.Kind {
	var isMacroExpansion: Bool {
		switch self {
		case .accessorAttachedMacroExpansion: return true
		case .memberAttributeAttachedMacroExpansion: return true
		case .freestandingMacroExpansion: return true
		case .memberAttachedMacroExpansion: return true
		case .peerAttachedMacroExpansion: return true
		case .conformanceAttachedMacroExpansion: return true
		case .extensionAttachedMacroExpansion, .bodyAttachedMacroExpansion, .preambleAttachedMacroExpansion: return true
		case .macroExpansionLoc: return true
		default: return false
		}
	}
}

extension Demangler {
	mutating func demangleMacroExpansion() throws -> SwiftSymbol {
		let kind: SwiftSymbol.Kind
		let isAttached: Bool
		let isFreestanding: Bool
		switch try scanner.readScalar() {
		case "a": (kind, isAttached, isFreestanding) = (.accessorAttachedMacroExpansion, true, false)
		case "r": (kind, isAttached, isFreestanding) = (.memberAttributeAttachedMacroExpansion, true, false)
		case "m": (kind, isAttached, isFreestanding) = (.memberAttachedMacroExpansion, true, false)
		case "p": (kind, isAttached, isFreestanding) = (.peerAttachedMacroExpansion, true, false)
		case "c": (kind, isAttached, isFreestanding) = (.conformanceAttachedMacroExpansion, true, false)
		case "b": (kind, isAttached, isFreestanding) = (.bodyAttachedMacroExpansion, true, false)
		case "e": (kind, isAttached, isFreestanding) = (.extensionAttachedMacroExpansion, true, false)
		case "q": (kind, isAttached, isFreestanding) = (.preambleAttachedMacroExpansion, true, false)
		case "f": (kind, isAttached, isFreestanding) = (.freestandingMacroExpansion, false, true)
		case "u": (kind, isAttached, isFreestanding) = (.macroExpansionUniqueName, false, false)
		case "X":
			let line = try demangleIndex()
			let col = try demangleIndex()
			let lineNode = SwiftSymbol(kind: .index, contents: .index(line))
			let colNode = SwiftSymbol(kind: .index, contents: .index(col))
			let buffer = try require(popNode(kind: .identifier))
			let module = try require(popNode(kind: .identifier))
			return SwiftSymbol(kind: .macroExpansionLoc, children: [module, buffer, lineNode, colNode])
		default:
			throw failure
		}
		
		let macroName = try require(popNode(kind: .identifier))
		let privateDiscriminator = isFreestanding ? popNode(kind: .privateDeclName) : nil
		let attachedName = isAttached ? popNode(where: { $0.isDeclName }) : nil
		let context = try popNode(where: { $0.isMacroExpansion }) ?? popContext()
		let discriminator = try demangleIndexAsNode()
		var result: SwiftSymbol
		if isAttached {
			result = SwiftSymbol(kind: kind, children: [context, try require(attachedName), macroName, discriminator])
		} else {
			result = SwiftSymbol(kind: kind, children: [context, macroName, discriminator])
		}
		if let privateDiscriminator {
			result.children.append(privateDiscriminator)
		}
		return result
	}
	
	mutating func demangleIntegerType() throws -> SwiftSymbol {
		if scanner.conditional(scalar: "n") {
			return SwiftSymbol(kind: .type, children: [SwiftSymbol(kind: .negativeInteger, contents: .index(0 &- (try demangleIndex())))])
		} else {
			return SwiftSymbol(kind: .type, children: [SwiftSymbol(kind: .integer, contents: .index(try demangleIndex()))])
		}
	}
	
	mutating func demangleObjCTypeName() throws -> SwiftSymbol {
		var type = SwiftSymbol(kind: .type)
		if scanner.conditional(scalar: "C") {
			let module: SwiftSymbol
			if scanner.conditional(scalar: "s") {
				module = SwiftSymbol(kind: .module, contents: .name(stdlibName))
			} else {
				module = try demangleIdentifier().changeKind(.module)
			}
			type.children.append(SwiftSymbol(kind: .class, children: [module, try demangleIdentifier()]))
		} else if scanner.conditional(scalar: "P") {
			let module: SwiftSymbol
			if scanner.conditional(scalar: "s") {
				module = SwiftSymbol(kind: .module, contents: .name(stdlibName))
			} else {
				module = try demangleIdentifier().changeKind(.module)
			}
			type.children.append(SwiftSymbol(kind: .protocolList, child: SwiftSymbol(kind: .typeList, child: SwiftSymbol(kind: .type, child: SwiftSymbol(kind: .protocol, children: [module, try demangleIdentifier()])))))
			try scanner.match(scalar: "_")
		} else {
			throw failure
		}
		try require(scanner.isAtEnd)
		return SwiftSymbol(kind: .global, child: SwiftSymbol(kind: .typeMangling, child: type))
	}
}

// MARK Demangle.cpp (Swift 3)

extension Demangler {
	
	mutating func demangleSwift3TopLevelSymbol() throws -> SwiftSymbol {
		reset()
		
		try scanner.match(string: "_T")
		var children = [SwiftSymbol]()
		
		switch (try scanner.readScalar(), try scanner.readScalar()) {
		case ("T", "S"):
			repeat {
				children.append(try demangleSwift3SpecializedAttribute())
				nodeStack.removeAll()
			} while scanner.conditional(string: "_TTS")
			try scanner.match(string: "_T")
		case ("T", "o"): children.append(SwiftSymbol(kind: .objCAttribute))
		case ("T", "O"): children.append(SwiftSymbol(kind: .nonObjCAttribute))
		case ("T", "D"): children.append(SwiftSymbol(kind: .dynamicAttribute))
		case ("T", "d"): children.append(SwiftSymbol(kind: .directMethodReferenceAttribute))
		case ("T", "v"): children.append(SwiftSymbol(kind: .vTableAttribute))
		default: try scanner.backtrack(count: 2)
		}
		
		children.append(try demangleSwift3Global())
		
		let remainder = scanner.remainder()
		if !remainder.isEmpty {
			children.append(SwiftSymbol(kind: .suffix, contents: .name(remainder)))
		}
		
		return SwiftSymbol(kind: .global, children: children)
	}
	
	mutating func demangleSwift3Global() throws -> SwiftSymbol {
		let c1 = try scanner.readScalar()
		let c2 = try scanner.readScalar()
		switch (c1, c2) {
		case ("M", "P"): return SwiftSymbol(kind: .genericTypeMetadataPattern, children: [try demangleSwift3Type()])
		case ("M", "a"): return SwiftSymbol(kind: .typeMetadataAccessFunction, children: [try demangleSwift3Type()])
		case ("M", "L"): return SwiftSymbol(kind: .typeMetadataLazyCache, children: [try demangleSwift3Type()])
		case ("M", "m"): return SwiftSymbol(kind: .metaclass, children: [try demangleSwift3Type()])
		case ("M", "n"): return SwiftSymbol(kind: .nominalTypeDescriptor, children: [try demangleSwift3Type()])
		case ("M", "f"): return SwiftSymbol(kind: .fullTypeMetadata, children: [try demangleSwift3Type()])
		case ("M", "p"): return SwiftSymbol(kind: .protocolDescriptor, children: [try demangleSwift3ProtocolName()])
		case ("M", _):
			try scanner.backtrack()
			return SwiftSymbol(kind: .typeMetadata, children: [try demangleSwift3Type()])
		case ("P", "A"):
			return SwiftSymbol(kind: scanner.conditional(scalar: "o") ? .partialApplyObjCForwarder : .partialApplyForwarder, children: scanner.conditional(string: "__T") ? [try demangleSwift3Global()] : [])
		case ("P", _): throw scanner.unexpectedError()
		case ("t", _):
			try scanner.backtrack()
			return SwiftSymbol(kind: .typeMangling, children: [try demangleSwift3Type()])
		case ("w", _):
			let c3 = try scanner.readScalar()
			let value = try require(ValueWitnessKind(code: String(c2) + String(c3))).rawValue
			return SwiftSymbol(kind: .valueWitness, children: [SwiftSymbol(kind: .index, contents: .index(value)), try demangleSwift3Type()])
		case ("W", "V"): return SwiftSymbol(kind: .valueWitnessTable, children: [try demangleSwift3Type()])
		case ("W", "v"): return SwiftSymbol(kind: .fieldOffset, children: [SwiftSymbol(kind: .directness, contents: .index(try scanner.readScalar() == "d" ? 0 : 1)), try demangleSwift3Entity()])
		case ("W", "P"): return SwiftSymbol(kind: .protocolWitnessTable, children: [try demangleSwift3ProtocolConformance()])
		case ("W", "G"): return SwiftSymbol(kind: .genericProtocolWitnessTable, children: [try demangleSwift3ProtocolConformance()])
		case ("W", "I"): return SwiftSymbol(kind: .genericProtocolWitnessTableInstantiationFunction, children: [try demangleSwift3ProtocolConformance()])
		case ("W", "l"): return SwiftSymbol(kind: .lazyProtocolWitnessTableAccessor, children: [try demangleSwift3Type(), try demangleSwift3ProtocolConformance()])
		case ("W", "L"): return SwiftSymbol(kind: .lazyProtocolWitnessTableCacheVariable, children: [try demangleSwift3Type(), try demangleSwift3ProtocolConformance()])
		case ("W", "a"): return SwiftSymbol(kind: .protocolWitnessTableAccessor, children: [try demangleSwift3ProtocolConformance()])
		case ("W", "t"): return SwiftSymbol(kind: .associatedTypeMetadataAccessor, children: [try demangleSwift3ProtocolConformance(), try demangleSwift3DeclName()])
		case ("W", "T"): return SwiftSymbol(kind: .associatedTypeWitnessTableAccessor, children: [try demangleSwift3ProtocolConformance(), try demangleSwift3DeclName(), try demangleSwift3ProtocolName()])
		case ("W", _): throw scanner.unexpectedError()
		case ("T","W"): return SwiftSymbol(kind: .protocolWitness, children: [try demangleSwift3ProtocolConformance(), try demangleSwift3Entity()])
		case ("T", "R"): fallthrough
		case ("T", "r"): return SwiftSymbol(kind: c2 == "R" ? SwiftSymbol.Kind.reabstractionThunkHelper : SwiftSymbol.Kind.reabstractionThunk, children: scanner.conditional(scalar: "G") ? [try demangleSwift3GenericSignature(), try demangleSwift3Type(), try demangleSwift3Type()] : [try demangleSwift3Type(), try demangleSwift3Type()])
		default:
			try scanner.backtrack(count: 2)
			return try demangleSwift3Entity()
		}
	}
	
	mutating func demangleSwift3SpecializedAttribute() throws -> SwiftSymbol {
		let c = try scanner.readScalar()
		var children = [SwiftSymbol]()
		if scanner.conditional(scalar: "q") {
			children.append(SwiftSymbol(kind: .isSerialized))
		}
		let passID = try scanner.read(where: { $0.isDigit })
		children.append(SwiftSymbol(kind: .specializationPassID, contents: .index(UInt64(passID.value - 48))))
		switch c {
		case "r": fallthrough
		case "g":
			while !scanner.conditional(scalar: "_") {
				var parameterChildren = [SwiftSymbol]()
				parameterChildren.append(try demangleSwift3Type())
				while !scanner.conditional(scalar: "_") {
					parameterChildren.append(try demangleSwift3ProtocolConformance())
				}
				children.append(SwiftSymbol(kind: .genericSpecializationParam, children: parameterChildren))
			}
			return SwiftSymbol(kind: c == "r" ? .genericSpecializationNotReAbstracted : .genericSpecialization, children: children)
		case "f":
			while !scanner.conditional(scalar: "_") {
				var paramChildren = [SwiftSymbol]()
				let c = try scanner.readScalar()
				switch (c, try scanner.readScalar()) {
				case ("n", "_"): break
				case ("c", "p"): paramChildren.append(contentsOf: try demangleSwift3FuncSigSpecializationConstantProp())
				case ("c", "l"):
					paramChildren.append(SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.closureProp.rawValue)))
					paramChildren.append(SwiftSymbol(kind: .functionSignatureSpecializationParamPayload, contents: try demangleSwift3Identifier().contents))
					while !scanner.conditional(scalar: "_") {
						paramChildren.append(try demangleSwift3Type())
					}
				case ("i", "_"): fallthrough
				case ("k", "_"): paramChildren.append(SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(c == "i" ? FunctionSigSpecializationParamKind.boxToValue.rawValue : FunctionSigSpecializationParamKind.boxToStack.rawValue)))
				default:
					try scanner.backtrack(count: 2)
					var value: UInt64 = 0
					value |= scanner.conditional(scalar: "d") ? FunctionSigSpecializationParamKind.dead.rawValue : 0
					value |= scanner.conditional(scalar: "g") ? FunctionSigSpecializationParamKind.ownedToGuaranteed.rawValue : 0
					value |= scanner.conditional(scalar: "o") ? FunctionSigSpecializationParamKind.guaranteedToOwned.rawValue : 0
					value |= scanner.conditional(scalar: "s") ? FunctionSigSpecializationParamKind.sroa.rawValue : 0
					try scanner.match(scalar: "_")
					paramChildren.append(SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(value)))
				}
				children.append(SwiftSymbol(kind: .functionSignatureSpecializationParam, children: paramChildren))
			}
			return SwiftSymbol(kind: .functionSignatureSpecialization, children: children)
		default: throw scanner.unexpectedError()
		}
	}
	
	mutating func demangleSwift3FuncSigSpecializationConstantProp() throws -> [SwiftSymbol] {
		switch (try scanner.readScalar(), try scanner.readScalar()) {
		case ("f", "r"):
			let name = SwiftSymbol(kind: .identifier, contents: try demangleSwift3Identifier().contents)
			try scanner.match(scalar: "_")
			let kind = SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.constantPropFunction.rawValue))
			return [kind, name]
		case ("g", _):
			try scanner.backtrack()
			let name = SwiftSymbol(kind: .identifier, contents: try demangleSwift3Identifier().contents)
			try scanner.match(scalar: "_")
			let kind = SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.constantPropGlobal.rawValue))
			return [kind, name]
		case ("i", _):
			try scanner.backtrack()
			let string = try scanner.readUntil(scalar: "_")
			try scanner.match(scalar: "_")
			let name = SwiftSymbol(kind: .functionSignatureSpecializationParamPayload, contents: .name(string))
			let kind = SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.constantPropInteger.rawValue))
			return [kind, name]
		case ("f", "l"):
			let string = try scanner.readUntil(scalar: "_")
			try scanner.match(scalar: "_")
			let name = SwiftSymbol(kind: .functionSignatureSpecializationParamPayload, contents: .name(string))
			let kind = SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.constantPropFloat.rawValue))
			return [kind, name]
		case ("s", "e"):
			var string: String
			switch try scanner.readScalar() {
			case "0": string = "u8"
			case "1": string = "u16"
			default: throw scanner.unexpectedError()
			}
			try scanner.match(scalar: "v")
			let name = SwiftSymbol(kind: .identifier, contents: try demangleSwift3Identifier().contents)
			let encoding = SwiftSymbol(kind: .functionSignatureSpecializationParamPayload, contents: .name(string))
			let kind = SwiftSymbol(kind: .functionSignatureSpecializationParamKind, contents: .index(FunctionSigSpecializationParamKind.constantPropString.rawValue))
			try scanner.match(scalar: "_")
			return [kind, encoding, name]
		default: throw scanner.unexpectedError()
		}
	}
	
	
	mutating func demangleSwift3ProtocolConformance() throws -> SwiftSymbol {
		let type = try demangleSwift3Type()
		let prot = try demangleSwift3ProtocolName()
		let context = try demangleSwift3Context()
		return SwiftSymbol(kind: .protocolConformance, children: [type, prot, context])
	}
	
	mutating func demangleSwift3ProtocolName() throws -> SwiftSymbol {
		let name: SwiftSymbol
		if scanner.conditional(scalar: "S") {
			let index = try demangleSwift3SubstitutionIndex()
			switch index.kind {
			case .protocol: name = index
			case .module: name = try demangleSwift3ProtocolNameGivenContext(context: index)
			default: throw scanner.unexpectedError()
			}
		} else if scanner.conditional(scalar: "s") {
			let stdlib = SwiftSymbol(kind: .module, contents: .name(stdlibName))
			name = try demangleSwift3ProtocolNameGivenContext(context: stdlib)
		} else {
			name = try demangleSwift3DeclarationName(kind: .protocol)
		}
		
		return SwiftSymbol(kind: .type, children: [name])
	}
	
	mutating func demangleSwift3ProtocolNameGivenContext(context: SwiftSymbol) throws -> SwiftSymbol {
		let name = try demangleSwift3DeclName()
		let result = SwiftSymbol(kind: .protocol, children: [context, name])
		nodeStack.append(result)
		return result
	}
	
	mutating func demangleSwift3NominalType() throws -> SwiftSymbol {
		switch try scanner.readScalar() {
		case "S": return try demangleSwift3SubstitutionIndex()
		case "V": return try demangleSwift3DeclarationName(kind: .structure)
		case "O": return try demangleSwift3DeclarationName(kind: .enum)
		case "C": return try demangleSwift3DeclarationName(kind: .class)
		case "P": return try demangleSwift3DeclarationName(kind: .protocol)
		default: throw scanner.unexpectedError()
		}
	}
	
	mutating func demangleSwift3BoundGenericArgs(nominalType initialNominal: SwiftSymbol) throws -> SwiftSymbol {
		guard var parentOrModule = initialNominal.children.first else { throw scanner.unexpectedError() }
		
		let nominalType: SwiftSymbol
		switch parentOrModule.kind {
		case .module: fallthrough
		case .function: fallthrough
		case .extension: nominalType = initialNominal
		default:
			parentOrModule = try demangleSwift3BoundGenericArgs(nominalType: parentOrModule)
			
			guard initialNominal.children.count > 1 else { throw scanner.unexpectedError() }
			nominalType = SwiftSymbol(kind: initialNominal.kind, children: [parentOrModule, initialNominal.children[1]])
		}
		
		var children = [SwiftSymbol]()
		while !scanner.conditional(scalar: "_") {
			children.append(try demangleSwift3Type())
		}
		if children.isEmpty {
			return nominalType
		}
		let args = SwiftSymbol(kind: .typeList, children: children)
		let unboundType = SwiftSymbol(kind: .type, children: [nominalType])
		switch nominalType.kind {
		case .class: return SwiftSymbol(kind: .boundGenericClass, children: [unboundType, args])
		case .structure: return SwiftSymbol(kind: .boundGenericStructure, children: [unboundType, args])
		case .enum: return SwiftSymbol(kind: .boundGenericEnum, children: [unboundType, args])
		default: throw scanner.unexpectedError()
		}
	}
	
	mutating func demangleSwift3Entity() throws -> SwiftSymbol {
		let isStatic = scanner.conditional(scalar: "Z")
		
		let basicKind: SwiftSymbol.Kind
		switch try scanner.readScalar() {
		case "F": basicKind = .function
		case "v": basicKind = .variable
		case "I": basicKind = .initializer
		case "i": basicKind = .subscript
		default:
			try scanner.backtrack()
			return try demangleSwift3NominalType()
		}
		
		let context = try demangleSwift3Context()
		let kind: SwiftSymbol.Kind
		let hasType: Bool
		var name: SwiftSymbol? = nil
		var wrapEntity: Bool = false
		
		let c = try scanner.readScalar()
		switch c {
		case "Z": (kind, hasType) = (.isolatedDeallocator, false)
		case "D": (kind, hasType) = (.deallocator, false)
		case "d": (kind, hasType) = (.destructor, false)
		case "e": (kind, hasType) = (.iVarInitializer, false)
		case "E": (kind, hasType) = (.iVarDestroyer, false)
		case "C": (kind, hasType) = (.allocator, true)
		case "c": (kind, hasType) = (.constructor, true)
		case "a": fallthrough
		case "l":
			wrapEntity = true
			switch try scanner.readScalar() {
			case "O": (kind, hasType, name) = (c == "a" ? .owningMutableAddressor : .owningAddressor, true, try demangleSwift3DeclName())
			case "o": (kind, hasType, name) = (c == "a" ? .nativeOwningMutableAddressor : .nativeOwningAddressor, true, try demangleSwift3DeclName())
			case "p": (kind, hasType, name) = (c == "a" ? .nativePinningMutableAddressor : .nativePinningAddressor, true, try demangleSwift3DeclName())
			case "u": (kind, hasType, name) = (c == "a" ? .unsafeMutableAddressor : .unsafeAddressor, true, try demangleSwift3DeclName())
			default: throw scanner.unexpectedError()
			}
		case "g": (kind, hasType, name, wrapEntity) = (.getter, true, try demangleSwift3DeclName(), true)
		case "G": (kind, hasType, name, wrapEntity) = (.globalGetter, true, try demangleSwift3DeclName(), true)
		case "s": (kind, hasType, name, wrapEntity) = (.setter, true, try demangleSwift3DeclName(), true)
		case "m": (kind, hasType, name, wrapEntity) = (.materializeForSet, true, try demangleSwift3DeclName(), true)
		case "w": (kind, hasType, name, wrapEntity) = (.willSet, true, try demangleSwift3DeclName(), true)
		case "W": (kind, hasType, name, wrapEntity) = (.didSet, true, try demangleSwift3DeclName(), true)
		case "U": (kind, hasType, name) = (.explicitClosure, true, SwiftSymbol(kind: .number, contents: .index(try demangleSwift3Index())))
		case "u": (kind, hasType, name) = (.implicitClosure, true, SwiftSymbol(kind: .number, contents: .index(try demangleSwift3Index())))
		case "A" where basicKind == .initializer: (kind, hasType, name) = (.defaultArgumentInitializer, false, SwiftSymbol(kind: .number, contents: .index(try demangleSwift3Index())))
		case "i" where basicKind == .initializer: (kind, hasType) = (.initializer, false)
		case _ where basicKind == .initializer: throw scanner.unexpectedError()
		default:
			try scanner.backtrack()
			(kind, hasType, name) = (basicKind, true, try demangleSwift3DeclName())
		}
		
		var entity = SwiftSymbol(kind: kind)
		if wrapEntity {
			var isSubscript = false
			switch name?.kind {
			case .some(.identifier):
				if name?.text == "subscript" {
					isSubscript = true
					name = nil
				}
			case .some(.privateDeclName):
				if let n = name, let first = n.children.at(0), let second = n.children.at(1), second.text == "subscript" {
					isSubscript = true
					name = SwiftSymbol(kind: .privateDeclName, children: [first])
				}
			default: break
			}
			var wrappedEntity: SwiftSymbol
			if isSubscript {
				wrappedEntity = SwiftSymbol(kind: .subscript, child: context)
			} else {
				wrappedEntity = SwiftSymbol(kind: .variable, child: context)
			}
			if !isSubscript, let n = name {
				wrappedEntity.children.append(n)
			}
			if hasType {
				wrappedEntity.children.append(try demangleSwift3Type())
			}
			if isSubscript, let n = name {
				wrappedEntity.children.append(n)
			}
			entity.children.append(wrappedEntity)
		} else {
			entity.children.append(context)
			if let n = name {
				entity.children.append(n)
			}
			if hasType {
				entity.children.append(try demangleSwift3Type())
			}
		}
		
		return isStatic ? SwiftSymbol(kind: .static, children: [entity]) : entity
	}
	
	mutating func demangleSwift3DeclarationName(kind: SwiftSymbol.Kind) throws -> SwiftSymbol {
		let result = SwiftSymbol(kind: kind, children: [try demangleSwift3Context(), try demangleSwift3DeclName()])
		nodeStack.append(result)
		return result
	}
	
	mutating func demangleSwift3Context() throws -> SwiftSymbol {
		switch try scanner.readScalar() {
		case "E": return SwiftSymbol(kind: .extension, children: [try demangleSwift3Module(), try demangleSwift3Context()])
		case "e":
			let module = try demangleSwift3Module()
			let signature = try demangleSwift3GenericSignature()
			let type = try demangleSwift3Context()
			return SwiftSymbol(kind: .extension, children: [module, type, signature])
		case "S": return try demangleSwift3SubstitutionIndex()
		case "s": return SwiftSymbol(kind: .module, children: [], contents: .name(stdlibName))
		case "G": return try demangleSwift3BoundGenericArgs(nominalType: demangleSwift3NominalType())
		case "F": fallthrough
		case "I": fallthrough
		case "v": fallthrough
		case "P": fallthrough
		case "Z": fallthrough
		case "C": fallthrough
		case "V": fallthrough
		case "O":
			try scanner.backtrack()
			return try demangleSwift3Entity()
		default:
			try scanner.backtrack()
			return try demangleSwift3Module()
		}
	}
	
	mutating func demangleSwift3Module() throws -> SwiftSymbol {
		switch try scanner.readScalar() {
		case "S": return try demangleSwift3SubstitutionIndex()
		case "s": return SwiftSymbol(kind: .module, children: [], contents: .name("Swift"))
		default:
			try scanner.backtrack()
			let module = try demangleSwift3Identifier(kind: .module)
			nodeStack.append(module)
			return module
		}
	}
	
	func swiftStdLibType(_ kind: SwiftSymbol.Kind, named: String) -> SwiftSymbol {
		return SwiftSymbol(kind: kind, children: [SwiftSymbol(kind: .module, contents: .name(stdlibName)), SwiftSymbol(kind: .identifier, contents: .name(named))])
	}
	
	mutating func demangleSwift3SubstitutionIndex() throws -> SwiftSymbol {
		switch try scanner.readScalar() {
		case "o": return SwiftSymbol(kind: .module, contents: .name(objcModule))
		case "C": return SwiftSymbol(kind: .module, contents: .name(cModule))
		case "a": return swiftStdLibType(.structure, named: "Array")
		case "b": return swiftStdLibType(.structure, named: "Bool")
		case "c": return swiftStdLibType(.structure, named: "UnicodeScalar")
		case "d": return swiftStdLibType(.structure, named: "Double")
		case "f": return swiftStdLibType(.structure, named: "Float")
		case "i": return swiftStdLibType(.structure, named: "Int")
		case "V": return swiftStdLibType(.structure, named: "UnsafeRawPointer")
		case "v": return swiftStdLibType(.structure, named: "UnsafeMutableRawPointer")
		case "P": return swiftStdLibType(.structure, named: "UnsafePointer")
		case "p": return swiftStdLibType(.structure, named: "UnsafeMutablePointer")
		case "q": return swiftStdLibType(.enum, named: "Optional")
		case "Q": return swiftStdLibType(.enum, named: "ImplicitlyUnwrappedOptional")
		case "R": return swiftStdLibType(.structure, named: "UnsafeBufferPointer")
		case "r": return swiftStdLibType(.structure, named: "UnsafeMutableBufferPointer")
		case "S": return swiftStdLibType(.structure, named: "String")
		case "u": return swiftStdLibType(.structure, named: "UInt")
		default:
			try scanner.backtrack()
			let index = try demangleSwift3Index()
			if index >= UInt64(nodeStack.count) {
				throw scanner.unexpectedError()
			}
			return nodeStack[Int(index)]
		}
	}
	
	mutating func demangleSwift3GenericSignature(isPseudo: Bool = false) throws -> SwiftSymbol {
		var children = [SwiftSymbol]()
		var c = try scanner.requirePeek()
		while c != "R" && c != "r" {
			children.append(SwiftSymbol(kind: .dependentGenericParamCount, contents: .index(scanner.conditional(scalar: "z") ? 0 : (try demangleSwift3Index() + 1))))
			c = try scanner.requirePeek()
		}
		if children.isEmpty {
			children.append(SwiftSymbol(kind: .dependentGenericParamCount, contents: .index(1)))
		}
		if !scanner.conditional(scalar: "r") {
			try scanner.match(scalar: "R")
			while !scanner.conditional(scalar: "r") {
				children.append(try demangleSwift3GenericRequirement())
			}
		}
		return SwiftSymbol(kind: isPseudo ? .dependentPseudogenericSignature : .dependentGenericSignature, children: children)
	}
	
	mutating func demangleSwift3GenericRequirement() throws -> SwiftSymbol {
		let constrainedType = SwiftSymbol(kind: .type, child: try demangleSwift3ConstrainedType())
		if scanner.conditional(scalar: "z") {
			return SwiftSymbol(kind: .dependentGenericSameTypeRequirement, children: [constrainedType, try demangleSwift3Type()])
		}
		
		if scanner.conditional(scalar: "l") {
			let name: String
			let kind: SwiftSymbol.Kind
			var size = UInt64.max
			var alignment = UInt64.max
			switch try scanner.readScalar() {
			case "U": (kind, name) = (.identifier, "U")
			case "R": (kind, name) = (.identifier, "R")
			case "N": (kind, name) = (.identifier, "N")
			case "T": (kind, name) = (.identifier, "T")
			case "B": (kind, name) = (.identifier, "B")
			case "E":
				(kind, name) = (.identifier, "E")
				size = try require(demangleNatural())
				try scanner.match(scalar: "_")
				alignment = try require(demangleNatural())
			case "e":
				(kind, name) = (.identifier, "e")
				size = try require(demangleNatural())
			case "M":
				(kind, name) = (.identifier, "M")
				size = try require(demangleNatural())
				try scanner.match(scalar: "_")
				alignment = try require(demangleNatural())
			case "m":
				(kind, name) = (.identifier, "m")
				size = try require(demangleNatural())
			default: throw failure
			}
			let second = SwiftSymbol(kind: kind, contents: .name(name))
			var reqt = SwiftSymbol(kind: .dependentGenericLayoutRequirement, children: [constrainedType, second])
			if size != UInt64.max {
				reqt.children.append(SwiftSymbol(kind: .number, contents: .index(size)))
				if alignment != UInt64.max {
					reqt.children.append(SwiftSymbol(kind: .number, contents: .index(alignment)))
				}
			}
			return reqt
		}
		
		let c = try scanner.requirePeek()
		let constraint: SwiftSymbol
		if c == "C" {
			constraint = try demangleSwift3Type()
		} else if c == "S" {
			try scanner.match(scalar: "S")
			let index = try demangleSwift3SubstitutionIndex()
			let typename: SwiftSymbol
			switch index.kind {
			case .protocol: fallthrough
			case .class: typename = index
			case .module: typename = try demangleSwift3ProtocolNameGivenContext(context: index)
			default: throw scanner.unexpectedError()
			}
			constraint = SwiftSymbol(kind: .type, children: [typename])
		} else {
			constraint = try demangleSwift3ProtocolName()
		}
		return SwiftSymbol(kind: .dependentGenericConformanceRequirement, children: [constrainedType, constraint])
	}
	
	mutating func demangleSwift3ConstrainedType() throws -> SwiftSymbol {
		if scanner.conditional(scalar: "w") {
			return try demangleSwift3AssociatedTypeSimple()
		} else if scanner.conditional(scalar: "W") {
			return try demangleSwift3AssociatedTypeCompound()
		}
		return try demangleSwift3GenericParamIndex()
	}
	
	mutating func demangleSwift3AssociatedTypeSimple() throws -> SwiftSymbol {
		let base = try demangleSwift3GenericParamIndex()
		return try demangleSwift3DependentMemberTypeName(base: SwiftSymbol(kind: .type, children: [base]))
	}
	
	mutating func demangleSwift3AssociatedTypeCompound() throws -> SwiftSymbol {
		var base = try demangleSwift3GenericParamIndex()
		while !scanner.conditional(scalar: "_") {
			let type = SwiftSymbol(kind: .type, children: [base])
			base = try demangleSwift3DependentMemberTypeName(base: type)
		}
		return base
	}
	
	mutating func demangleSwift3GenericParamIndex() throws -> SwiftSymbol {
		let depth: UInt64
		let index: UInt64
		switch try scanner.readScalar() {
		case "d": (depth, index) = (try demangleSwift3Index() + 1, try demangleSwift3Index())
		case "x": (depth, index) = (0, 0)
		default:
			try scanner.backtrack()
			(depth, index) = (0, try demangleSwift3Index() + 1)
		}
		return SwiftSymbol(kind: .dependentGenericParamType, children: [SwiftSymbol(kind: .index, contents: .index(depth)), SwiftSymbol(kind: .index, contents: .index(index))])
	}
	
	mutating func demangleSwift3DependentMemberTypeName(base: SwiftSymbol) throws -> SwiftSymbol {
		let associatedType: SwiftSymbol
		if scanner.conditional(scalar: "S") {
			associatedType = try demangleSwift3SubstitutionIndex()
		} else {
			var prot: SwiftSymbol? = nil
			if scanner.conditional(scalar: "P") {
				prot = try demangleSwift3ProtocolName()
			}
			let identifier = try demangleSwift3Identifier()
			if let p = prot {
				associatedType = SwiftSymbol(kind: .dependentAssociatedTypeRef, children: [identifier, p])
			} else {
				associatedType = SwiftSymbol(kind: .dependentAssociatedTypeRef, children: [identifier])
			}
			nodeStack.append(associatedType)
		}
		
		return SwiftSymbol(kind: .dependentMemberType, children: [base, associatedType])
	}
	
	mutating func demangleSwift3DeclName() throws -> SwiftSymbol {
		switch try scanner.readScalar() {
		case "L": return SwiftSymbol(kind: .localDeclName, children: [SwiftSymbol(kind: .number, contents: .index(try demangleSwift3Index())), try demangleSwift3Identifier()])
		case "P": return SwiftSymbol(kind: .privateDeclName, children: [try demangleSwift3Identifier(), try demangleSwift3Identifier()])
		default:
			try scanner.backtrack()
			return try demangleSwift3Identifier()
		}
	}
	
	mutating func demangleSwift3Index() throws -> UInt64 {
		if scanner.conditional(scalar: "_") {
			return 0
		}
		let index = try scanner.readInt()
		try require(index < UInt64.max)
		let value = index + 1
		try scanner.match(scalar: "_")
		return value
	}
	
	mutating func demangleSwift3Type() throws -> SwiftSymbol {
		let type: SwiftSymbol
		switch try scanner.readScalar() {
		case "B":
			switch try scanner.readScalar() {
			case "b": type = SwiftSymbol(kind: .builtinTypeName, contents: .name("Builtin.BridgeObject"))
			case "B": type = SwiftSymbol(kind: .builtinTypeName, contents: .name("Builtin.UnsafeValueBuffer"))
			case "f":
				let size = try scanner.readInt()
				try scanner.match(scalar: "_")
				type = SwiftSymbol(kind: .builtinTypeName, contents: .name("Builtin.FPIEEE\(size)"))
			case "i":
				let size = try scanner.readInt()
				try scanner.match(scalar: "_")
				type = SwiftSymbol(kind: .builtinTypeName, contents: .name("Builtin.Int\(size)"))
			case "v":
				let elements = try scanner.readInt()
				try scanner.match(scalar: "B")
				let name: String
				let size: String
				let c = try scanner.readScalar()
				switch c {
				case "p": (name, size) = ("xRawPointer", "")
				case "i": fallthrough
				case "f":
					(name, size) = (c == "i" ? "xInt" : "xFPIEEE", try "\(scanner.readInt())")
					try scanner.match(scalar: "_")
				default: throw scanner.unexpectedError()
				}
				type = SwiftSymbol(kind: .builtinTypeName, contents: .name("Builtin.Vec\(elements)\(name)\(size)"))
			case "O": type = SwiftSymbol(kind: .builtinTypeName, contents: .name("Builtin.UnknownObject"))
			case "o": type = SwiftSymbol(kind: .builtinTypeName, contents: .name("Builtin.NativeObject"))
			case "t": type = SwiftSymbol(kind: .builtinTypeName, contents: .name("Builtin.SILToken"))
			case "p": type = SwiftSymbol(kind: .builtinTypeName, contents: .name("Builtin.RawPointer"))
			case "w": type = SwiftSymbol(kind: .builtinTypeName, contents: .name("Builtin.Word"))
			default: throw scanner.unexpectedError()
			}
		case "a": type = try demangleSwift3DeclarationName(kind: .typeAlias)
		case "b": type = try demangleSwift3FunctionType(kind: .objCBlock)
		case "c": type = try demangleSwift3FunctionType(kind: .cFunctionPointer)
		case "D": type = SwiftSymbol(kind: .dynamicSelf, children: [try demangleSwift3Type()])
		case "E":
			guard try scanner.readScalars(count: 2) == "RR" else { throw scanner.unexpectedError() }
			type = SwiftSymbol(kind: .errorType, children: [], contents: .name(""))
		case "F": type = try demangleSwift3FunctionType(kind: .functionType)
		case "f": type = try demangleSwift3FunctionType(kind: .uncurriedFunctionType)
		case "G": type = try demangleSwift3BoundGenericArgs(nominalType: demangleSwift3NominalType())
		case "X":
			let c = try scanner.readScalar()
			switch c {
			case "b": type = SwiftSymbol(kind: .silBoxType, children: [try demangleSwift3Type()])
			case "B":
				var signature: SwiftSymbol? = nil
				if scanner.conditional(scalar: "G") {
					signature = try demangleSwift3GenericSignature(isPseudo: false)
				}
				var layout = SwiftSymbol(kind: .silBoxLayout)
				while !scanner.conditional(scalar: "_") {
					let kind: SwiftSymbol.Kind
					switch try scanner.readScalar() {
					case "m": kind = .silBoxMutableField
					case "i": kind = .silBoxImmutableField
					default: throw failure
					}
					let type = try demangleType()
					let field = SwiftSymbol(kind: kind, child: type)
					layout.children.append(field)
				}
				var genericArgs: SwiftSymbol? = nil
				if signature != nil {
					var ga = SwiftSymbol(kind: .typeList)
					while !scanner.conditional(scalar: "_") {
						let type = try demangleType()
						ga.children.append(type)
					}
					genericArgs = ga
				}
				var boxType = SwiftSymbol(kind: .silBoxTypeWithLayout, child: layout)
				if let s = signature, let ga = genericArgs {
					boxType.children.append(s)
					boxType.children.append(ga)
				}
				return boxType
			case "P" where scanner.conditional(scalar: "M"): fallthrough
			case "M":
				let value: String
				switch try scanner.readScalar() {
				case "t": value = "@thick"
				case "T": value = "@thin"
				case "o": value = "@objc_metatype"
				default: throw scanner.unexpectedError()
				}
				type = SwiftSymbol(kind: c == "P" ? .existentialMetatype : .metatype, children: [SwiftSymbol(kind: .metatypeRepresentation, contents: .name(value)), try demangleSwift3Type()])
			case "P":
				var children = [SwiftSymbol]()
				while !scanner.conditional(scalar: "_") {
					children.append(try demangleSwift3ProtocolName())
				}
				type = SwiftSymbol(kind: .protocolList, children: [SwiftSymbol(kind: .typeList)])
			case "f": type = try demangleSwift3FunctionType(kind: .thinFunctionType)
			case "o": type = SwiftSymbol(kind: .unowned, children: [try demangleSwift3Type()])
			case "u": type = SwiftSymbol(kind: .unmanaged, children: [try demangleSwift3Type()])
			case "w": type = SwiftSymbol(kind: .weak, children: [try demangleSwift3Type()])
			case "F":
				var children = [SwiftSymbol]()
				children.append(SwiftSymbol(kind: .implConvention, contents: .name(try demangleSwift3ImplConvention(kind: .implConvention))))
				if scanner.conditional(scalar: "C") {
					let name: String
					switch try scanner.readScalar() {
					case "b": name = "block"
					case "c": name = "c"
					case "m": name = "method"
					case "O": name = "objc_method"
					case "w": name = "witness_method"
					default: throw scanner.unexpectedError()
					}
					children.append(SwiftSymbol(kind: .implFunctionConvention, child: SwiftSymbol(kind: .implFunctionConventionName, contents: .name(name))))
				}
				if scanner.conditional(scalar: "G") {
					children.append(try demangleSwift3GenericSignature(isPseudo: false))
				} else if scanner.conditional(scalar: "g") {
					children.append(try demangleSwift3GenericSignature(isPseudo: true))
				}
				try scanner.match(scalar: "_")
				while !scanner.conditional(scalar: "_") {
					children.append(try demangleSwift3ImplParameterOrResult(kind: .implParameter))
				}
				while !scanner.conditional(scalar: "_") {
					children.append(try demangleSwift3ImplParameterOrResult(kind: .implResult))
				}
				type = SwiftSymbol(kind: .implFunctionType, children: children)
			default: throw scanner.unexpectedError()
			}
		case "K": type = try demangleSwift3FunctionType(kind: .autoClosureType)
		case "M": type = SwiftSymbol(kind: .metatype, children: [try demangleSwift3Type()])
		case "P" where scanner.conditional(scalar: "M"): type = SwiftSymbol(kind: .existentialMetatype, children: [try demangleSwift3Type()])
		case "P":
			var children = [SwiftSymbol]()
			while !scanner.conditional(scalar: "_") {
				children.append(try demangleSwift3ProtocolName())
			}
			type = SwiftSymbol(kind: .protocolList, children: [SwiftSymbol(kind: .typeList, children: children)])
		case "Q":
			if scanner.conditional(scalar: "u") {
				type = SwiftSymbol(kind: .opaqueReturnType)
			} else if scanner.conditional(scalar: "U") {
				let index = try demangleIndex()
				type = SwiftSymbol(kind: .opaqueReturnType, child: SwiftSymbol(kind: .opaqueReturnTypeIndex, contents: .index(index)))
			} else {
				type = try demangleSwift3ArchetypeType()
			}
		case "q":
			let c = try scanner.requirePeek()
			if c != "d" && c != "_" && !c.isDigit {
				type = try demangleSwift3DependentMemberTypeName(base: demangleSwift3Type())
			} else {
				type = try demangleSwift3GenericParamIndex()
			}
		case "x": type = SwiftSymbol(kind: .dependentGenericParamType, children: [SwiftSymbol(kind: .index, contents: .index(0)), SwiftSymbol(kind: .index, contents: .index(0))])
		case "w": type = try demangleSwift3AssociatedTypeSimple()
		case "W": type = try demangleSwift3AssociatedTypeCompound()
		case "R": type = SwiftSymbol(kind: .inOut, children: try demangleSwift3Type().children)
		case "k": type = SwiftSymbol(kind: .noDerivative, children: try demangleSwift3Type().children)
		case "S": type = try demangleSwift3SubstitutionIndex()
		case "T": type = try demangleSwift3Tuple(variadic: false)
		case "t": type = try demangleSwift3Tuple(variadic: true)
		case "u": type = SwiftSymbol(kind: .dependentGenericType, children: [try demangleSwift3GenericSignature(), try demangleSwift3Type()])
		case "C": type = try demangleSwift3DeclarationName(kind: .class)
		case "V": type = try demangleSwift3DeclarationName(kind: .structure)
		case "O": type = try demangleSwift3DeclarationName(kind: .enum)
		default: throw scanner.unexpectedError()
		}
		return SwiftSymbol(kind: .type, children: [type])
	}
	
	mutating func demangleSwift3ArchetypeType() throws -> SwiftSymbol {
		switch try scanner.readScalar() {
		case "Q":
			let result = SwiftSymbol(kind: .associatedTypeRef, children: [try demangleSwift3ArchetypeType(), try demangleSwift3Identifier()])
			nodeStack.append(result)
			return result
		case "S":
			let index = try demangleSwift3SubstitutionIndex()
			let result = SwiftSymbol(kind: .associatedTypeRef, children: [index, try demangleSwift3Identifier()])
			nodeStack.append(result)
			return result
		case "s":
			let root = SwiftSymbol(kind: .module, contents: .name(stdlibName))
			let result = SwiftSymbol(kind: .associatedTypeRef, children: [root, try demangleSwift3Identifier()])
			nodeStack.append(result)
			return result
		default: throw scanner.unexpectedError()
		}
	}
	
	mutating func demangleSwift3ImplConvention(kind: SwiftSymbol.Kind) throws -> String {
		let scalar = try scanner.readScalar()
		switch (scalar, (kind == .implErrorResult ? .implResult : kind)) {
		case ("a", .implResult): return "@autoreleased"
		case ("d", .implConvention): return "@callee_unowned"
		case ("d", _): return "@unowned"
		case ("D", .implResult): return "@unowned_inner_pointer"
		case ("g", .implParameter): return "@guaranteed"
		case ("e", .implParameter): return "@deallocating"
		case ("g", .implConvention): return "@callee_guaranteed"
		case ("i", .implParameter): return "@in"
		case ("i", .implResult): return "@out"
		case ("l", .implParameter): return "@inout"
		case ("o", .implConvention): return "@callee_owned"
		case ("o", _): return "@owned"
		case ("t", .implConvention): return "@convention(thin)"
		default: throw scanner.unexpectedError()
		}
	}
	
	mutating func demangleSwift3ImplParameterOrResult(kind: SwiftSymbol.Kind) throws -> SwiftSymbol {
		var k: SwiftSymbol.Kind
		if scanner.conditional(scalar: "z") {
			if case .implResult = kind {
				k = .implErrorResult
			} else {
				throw scanner.unexpectedError()
			}
		} else {
			k = kind
		}
		
		let convention = try demangleSwift3ImplConvention(kind: k)
		let type = try demangleSwift3Type()
		let conventionNode = SwiftSymbol(kind: .implConvention, contents: .name(convention))
		return SwiftSymbol(kind: k, children: [conventionNode, type])
	}
	
	
	mutating func demangleSwift3Tuple(variadic: Bool) throws -> SwiftSymbol {
		var children = [SwiftSymbol]()
		while !scanner.conditional(scalar: "_") {
			var elementChildren = [SwiftSymbol]()
			let peek = try scanner.requirePeek()
			if (peek >= "0" && peek <= "9") || peek == "o" {
				elementChildren.append(try demangleSwift3Identifier(kind: .tupleElementName))
			}
			elementChildren.append(try demangleSwift3Type())
			children.append(SwiftSymbol(kind: .tupleElement, children: elementChildren))
		}
		if variadic, var last = children.popLast() {
			last.children.insert(SwiftSymbol(kind: .variadicMarker), at: 0)
			children.append(last)
		}
		return SwiftSymbol(kind: .tuple, children: children)
	}
	
	mutating func demangleSwift3FunctionType(kind: SwiftSymbol.Kind) throws -> SwiftSymbol {
		var children = [SwiftSymbol]()
		if scanner.conditional(scalar: "z") {
			children.append(SwiftSymbol(kind: .throwsAnnotation))
		}
		children.append(SwiftSymbol(kind: .argumentTuple, children: [try demangleSwift3Type()]))
		children.append(SwiftSymbol(kind: .returnType, children: [try demangleSwift3Type()]))
		return SwiftSymbol(kind: kind, children: children)
	}
	
	mutating func demangleSwift3Identifier(kind: SwiftSymbol.Kind? = nil) throws -> SwiftSymbol {
		let isPunycode = scanner.conditional(scalar: "X")
		let k: SwiftSymbol.Kind
		let isOperator: Bool
		if scanner.conditional(scalar: "o") {
			guard kind == nil else { throw scanner.unexpectedError() }
			switch try scanner.readScalar() {
			case "p": (isOperator, k) = (true, .prefixOperator)
			case "P": (isOperator, k) = (true, .postfixOperator)
			case "i": (isOperator, k) = (true, .infixOperator)
			default: throw scanner.unexpectedError()
			}
		} else {
			(isOperator, k) = (false, kind ?? SwiftSymbol.Kind.identifier)
		}
		
		let length = try require(demangleNatural())
		var identifier = try scanner.readUTF8(count: Int(length))
		if isPunycode {
			identifier = try Punycode.decodePunycodeUTF8(identifier)
		}
		if isOperator {
			let source = identifier
			identifier = ""
			for scalar in source.unicodeScalars {
				switch scalar {
				case "a": identifier.unicodeScalars.append("&" as UnicodeScalar)
				case "c": identifier.unicodeScalars.append("@" as UnicodeScalar)
				case "d": identifier.unicodeScalars.append("/" as UnicodeScalar)
				case "e": identifier.unicodeScalars.append("=" as UnicodeScalar)
				case "g": identifier.unicodeScalars.append(">" as UnicodeScalar)
				case "l": identifier.unicodeScalars.append("<" as UnicodeScalar)
				case "m": identifier.unicodeScalars.append("*" as UnicodeScalar)
				case "n": identifier.unicodeScalars.append("!" as UnicodeScalar)
				case "o": identifier.unicodeScalars.append("|" as UnicodeScalar)
				case "p": identifier.unicodeScalars.append("+" as UnicodeScalar)
				case "q": identifier.unicodeScalars.append("?" as UnicodeScalar)
				case "r": identifier.unicodeScalars.append("%" as UnicodeScalar)
				case "s": identifier.unicodeScalars.append("-" as UnicodeScalar)
				case "t": identifier.unicodeScalars.append("~" as UnicodeScalar)
				case "x": identifier.unicodeScalars.append("^" as UnicodeScalar)
				case "z": identifier.unicodeScalars.append("." as UnicodeScalar)
				default:
					if scalar.value >= 128 {
						identifier.unicodeScalars.append(scalar)
					} else {
						throw scanner.unexpectedError()
					}
				}
			}
		}
		
		return SwiftSymbol(kind: k, children: [], contents: .name(identifier))
	}
}

func getManglingPrefixLength<C: Collection>(_ scalars: C) -> Int where C.Iterator.Element == UnicodeScalar {
    var scanner = ScalarScanner(scalars: scalars)
    if scanner.conditional(string: "_T0") || scanner.conditional(string: "_$S") || scanner.conditional(string: "_$s") || scanner.conditional(string: "_$e") {
        return 3
    } else if scanner.conditional(string: "$S") || scanner.conditional(string: "$s") || scanner.conditional(string: "$e") {
        return 2
    } else if scanner.conditional(string: "@__swiftmacro_") {
        return 13
    }

    return 0
}
