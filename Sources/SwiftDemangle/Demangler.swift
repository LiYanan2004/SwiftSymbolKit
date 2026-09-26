import Foundation

// MARK: Demangler.h

let stdlibName = "Swift"
let objcModule = "__C"
let cModule = "__C_Synthesized"
let lldbExpressionsModuleNamePrefix = "__lldb_expr_"
let maxRepeatCount = 2048
let maxNumWords = 26

struct Demangler<C> where C: Collection, C.Iterator.Element == UnicodeScalar {
	var scanner: ScalarScanner<C>
	var nameStack: [SwiftSymbol] = []
	var substitutions: [SwiftSymbol] = []
	var words: [String] = []
	var symbolicReferences: [Int32] = []
	var isOldFunctionTypeMangling: Bool = false
	var symbolicReferenceResolver: ((Int32, Int) throws -> SwiftSymbol)? = nil
	var flavor: ManglingFlavor = .default
	
	init(scalars: C) {
		scanner = ScalarScanner(scalars: scalars)
	}
}

