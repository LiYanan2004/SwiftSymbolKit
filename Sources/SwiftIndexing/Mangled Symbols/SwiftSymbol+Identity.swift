import SwiftDemangle

package extension SwiftSymbol {
    var isTypeDeclaration: Bool {
        switch kind {
            case .structure: return true
            case .enum: return true
            case .class: return true
            case .protocol: return true
            case .typeAlias: return true
            default: return false
        }
    }
    
    /// Structural identity is independent of the printer, hash seeds and linker prefixes.
    /// Normalize only allocating/nonallocating variants known to describe one declaration.
    var declarationKey: String {
        let normalizedKind: Kind
        switch kind {
            case .allocator: normalizedKind = .constructor
            case .deallocator: normalizedKind = .destructor
            default: normalizedKind = kind
        }
        let payload: String
        switch contents {
            case .none: payload = "none"
            case .index(let index): payload = "index:\(index)"
            case .name(let name): payload = "name:\(name)"
        }
        let fields = [String(describing: normalizedKind), payload] + children.map(\.declarationKey)
        return "\(fields.count)[" + fields.map { "\($0.utf8.count):\($0)" }.joined() + "]"
    }
}
