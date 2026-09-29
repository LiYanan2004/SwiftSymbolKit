import SwiftDemangle

/// The ABI identity of a flat Clang nominal type. Class and protocol names can coincide.
public struct ClangTypeIdentity: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case `class`, structure, `enum`, `protocol`, typeAlias
    }
    
    public let kind: Kind
    public let name: String
    
    public init(kind: Kind, name: String) {
        self.kind = kind
        self.name = name
    }
    
    public init?(_ node: DemangledNode) {
        guard node.children.count == 2,
              node.children[0].kind == .module,
              case .name("__C") = node.children[0].contents,
              node.children[1].kind == .identifier,
              case .name(let name) = node.children[1].contents else { return nil }
        let kind: Kind
        switch node.kind {
            case .class: kind = .class
            case .structure: kind = .structure
            case .enum: kind = .enum
            case .protocol: kind = .protocol
            case .typeAlias: kind = .typeAlias
            default: return nil
        }
        self.init(kind: kind, name: name)
    }
    
    /// Collects requests without altering the original demangle tree.
    public static func occurrences(in node: DemangledNode) -> Set<Self> {
        var identities = Set(node.children.flatMap { occurrences(in: $0) })
        if let identity = Self(node) { identities.insert(identity) }
        return identities
    }
    
    /// Accepts only the complete parameter of the generated probe, including a
    /// single protocol existential. Nested mentions in Optional/Array do not match.
    package static func probeIdentity(mangledSymbol: String) -> Self? {
        guard var node = try? DemangledNode(mangledSymbol) else { return nil }
        guard node.kind == .global else { return nil }
        for kind: DemangledNode.Kind in [.function, .type, .functionType, .argumentTuple, .type] {
            let matches = node.children.filter { $0.kind == kind }
            guard matches.count == 1 else { return nil }
            node = matches[0]
        }
        guard node.children.count == 1 else { return nil }
        node = node.children[0]
        if node.kind == .protocolList {
            for kind: DemangledNode.Kind in [.typeList, .type, .protocol] {
                guard node.children.count == 1, node.children[0].kind == kind else { return nil }
                node = node.children[0]
            }
        }
        return Self(node)
    }
}
