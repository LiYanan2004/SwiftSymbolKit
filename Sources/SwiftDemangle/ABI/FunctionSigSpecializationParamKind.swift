//
//  FunctionSigSpecializationParamKind.swift
//  SwiftSymbolKit
//
//  Created by Yanan Li on 2026/9/29.
//

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
