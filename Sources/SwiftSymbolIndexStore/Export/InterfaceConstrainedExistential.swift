import SwiftIndexing

/// Same-type constraints that can be expressed using primary associated type syntax.
struct InterfaceConstrainedExistential {
    let protocolType: DemangledNode
    let associatedTypeNames: [String]
    let arguments: [DemangledNode]

    init(_ node: DemangledNode) throws {
        guard node.kind == .constrainedExistential, node.children.count == 2,
              node.children[1].kind == .constrainedExistentialRequirementList else {
            throw InterfaceTypeRenderer.RenderingError("Invalid constrained existential")
        }
        let base = node.children[0].interfaceUnderlyingType
        guard base.kind == .protocolList, base.children.count == 1,
              base.children[0].kind == .typeList, base.children[0].children.count == 1 else {
            throw InterfaceTypeRenderer.RenderingError("Constrained existential requires a single protocol")
        }
        let protocolType = base.children[0].children[0].interfaceUnderlyingType
        guard protocolType.kind == .protocol, protocolType.children.count == 2 else {
            throw InterfaceTypeRenderer.RenderingError("Invalid constrained existential protocol")
        }
        var constraints: [String: DemangledNode] = [:]
        var names: [String] = []
        for requirement in node.children[1].children {
            guard requirement.kind == .dependentGenericSameTypeRequirement, requirement.children.count == 2 else {
                throw InterfaceTypeRenderer.RenderingError("Unsupported constrained existential requirement")
            }
            let member = requirement.children[0].interfaceUnderlyingType
            guard member.kind == .dependentMemberType, member.children.count == 2,
                  member.children[1].kind == .dependentAssociatedTypeRef,
                  let name = member.children[1].children.first else {
                throw InterfaceTypeRenderer.RenderingError("Expected a direct associated type constraint")
            }
            let root = member.children[0].interfaceUnderlyingType
            // Protocol member symbols can use the generic Self parameter for this constraint.
            let isGenericSelf = try root.kind == .dependentGenericParamType
                && root.parameterPosition() == (0, 0)
            guard root.kind == .constrainedExistentialSelf || isGenericSelf else {
                throw InterfaceTypeRenderer.RenderingError("Unsupported constrained existential associated type path")
            }
            let associatedTypeName = try name.nameValue()
            guard constraints.updateValue(requirement.children[1], forKey: associatedTypeName) == nil else {
                throw InterfaceTypeRenderer.RenderingError("Duplicate constrained existential associated type")
            }
            names.append(associatedTypeName)
        }
        guard !names.isEmpty else {
            throw InterfaceTypeRenderer.RenderingError("Missing constrained existential requirements")
        }
        // Preserve encoded requirement order for reconstruction. Source-level primary
        // associated type order requires declaration information from outside mangling.
        self.protocolType = protocolType
        associatedTypeNames = names
        arguments = names.compactMap { constraints[$0] }
    }

    static func occurrences(in node: DemangledNode) -> [InterfaceConstrainedExistential] {
        let current = node.kind == .constrainedExistential ? (try? Self(node)) : nil
        return (current.map { [$0] } ?? []) + node.children.flatMap { occurrences(in: $0) }
    }
}
