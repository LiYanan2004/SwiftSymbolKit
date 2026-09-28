//
//  DemangleGenericRequirementConstraintKind.swift
//  SwiftSymbolKit
//
//  Created by Yanan Li on 2026/9/29.
//

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
