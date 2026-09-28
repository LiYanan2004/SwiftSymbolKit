//
//  SpecializationPass.swift
//  SwiftSymbolKit
//
//  Created by Yanan Li on 2026/9/29.
//

enum SpecializationPass {
	case allocBoxToStack
	case closureSpecializer
	case capturePromotion
	case capturePropagation
	case functionSignatureOpts
	case genericSpecializer
	case moveDiagnosticInOutToOut
	case asyncDemotion
	case packSpecialization
	case embeddedWitnessCallSpecialization
}
