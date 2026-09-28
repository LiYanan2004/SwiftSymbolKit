import SwiftDemangle

/// Reads the stable Swift descriptor ABI, independently of any runtime parser.
struct OpaqueTypeDescriptorReader {
    let image: LoadedMachOImage
    
    func read(at descriptor: UInt64, declaration: DemangledNode) throws -> [OpaqueReturnType] {
        let flags: UInt32 = try image.value(at: descriptor)
        // ContextDescriptorKind::OpaqueType = 4; bit 7 means generic; bits
        // 8...15 are the version; bit 5 introduces invertible protocol data.
        // https://github.com/swiftlang/swift/blob/swift-6.2-RELEASE/include/swift/ABI/MetadataValues.h
        guard flags & 0x1f == 4, flags & 0x80 != 0, flags & 0xff20 == 0 else {
            throw LoadedMachOImage.ReadError("Unsupported opaque descriptor flags")
        }
        let ordinals = opaqueOrdinals(in: declaration)
        guard !ordinals.isEmpty else { throw LoadedMachOImage.ReadError("Declaration has no opaque result") }
        let depth = try parameterDepth(descriptor: descriptor, opaqueParameterCount: (ordinals.max() ?? 0) + 1)
        // TargetOpaqueTypeDescriptor: 8-byte ContextDescriptor, then the
        // 8-byte GenericContextDescriptorHeader, one byte per parameter,
        // 4-byte alignment, and 12 bytes per generic requirement.
        // https://github.com/swiftlang/swift/blob/swift-6.2-RELEASE/include/swift/ABI/Metadata.h
        // https://github.com/swiftlang/swift/blob/swift-6.2-RELEASE/include/swift/ABI/GenericContext.h
        let parameterCount = Int(try image.value(at: descriptor + 8, as: UInt16.self))
        let requirementCount = Int(try image.value(at: descriptor + 10, as: UInt16.self))
        let genericFlags: UInt16 = try image.value(at: descriptor + 14)
        guard genericFlags == 0 else { throw LoadedMachOImage.ReadError("Generic packs, values, or conditional inverted protocols are unsupported") }
        let parameterDescriptors = try image.bytes(at: descriptor + 16, count: parameterCount)
        guard parameterDescriptors.allSatisfy({ $0 & 0x3f == 0 }) else { throw LoadedMachOImage.ReadError("Unsupported generic parameter kind") }
        let requirementsStart = (descriptor + 16 + UInt64(parameterCount) + 3) & ~3
        var constraints: [Int: [DemangledNode]] = [:]
        var sameTypes: [Int: [DemangledNode]] = [:]
        for index in 0..<requirementCount {
            let requirement = requirementsStart + UInt64(index * 12)
            let requirementFlags: UInt32 = try image.value(at: requirement)
            let subject = try type(at: image.relative(at: requirement + 4))
            let subjectOrdinals = parameters(in: subject, atDepth: depth).intersection(ordinals)
            // GenericRequirementKind: protocol=0, sameType=1, baseClass=2.
            // The remaining requirements cannot be silently dropped when they
            // constrain an opaque parameter. Outer parameter requirements are
            // already represented by the declaration's mangled signature.
            switch requirementFlags & 0x1f {
                case 0 where !subjectOrdinals.isEmpty:
                    guard let ordinal = rootParameter(subject, depth: depth), ordinals.contains(ordinal) else {
                        throw LoadedMachOImage.ReadError("Associated-type protocol requirements cannot be spelled as an opaque constraint")
                    }
                    let protocolAddress = try image.relative(at: requirement + 8, indirectable: true, protocolReference: true)
                    constraints[ordinal, default: []].append(try contextType(at: protocolAddress))
                case 2 where !subjectOrdinals.isEmpty:
                    guard let ordinal = rootParameter(subject, depth: depth), ordinals.contains(ordinal) else {
                        throw LoadedMachOImage.ReadError("Associated-type superclass requirement is unsupported")
                    }
                    constraints[ordinal, default: []].insert(try type(at: image.relative(at: requirement + 8)), at: 0)
                case 1:
                    let replacement = try type(at: image.relative(at: requirement + 8))
                    let affected = subjectOrdinals.union(parameters(in: replacement, atDepth: depth).intersection(ordinals))
                    for ordinal in affected {
                        sameTypes[ordinal, default: []].append(.init(kind: .dependentGenericSameTypeRequirement, children: [subject, replacement]))
                    }
                default:
                    if !subjectOrdinals.isEmpty { throw LoadedMachOImage.ReadError("Unsupported opaque generic requirement: \(requirementFlags & 0x1f)") }
            }
        }
        let underlyingStart = requirementsStart + UInt64(requirementCount * 12)
        // Kind-specific flags count all underlying arguments: replacement
        // types first, then conformance witnesses. Only opaque ordinals index
        // replacement types; witness entries must not be demangled as types.
        return ordinals.sorted().map { ordinal in
            let underlying: DemangledNode?
            if ordinal < Int(flags >> 16) {
                underlying = try? type(at: image.relative(at: underlyingStart + UInt64(ordinal * 4)))
            } else { underlying = nil }
            return OpaqueReturnType(ordinal: ordinal, parameterDepth: depth,
                                    constraints: constraints[ordinal] ?? [], sameTypeRequirements: sameTypes[ordinal] ?? [], underlyingType: underlying)
        }
    }
    
    func type(at address: UInt64, depth: Int = 0) throws -> DemangledNode {
        guard depth < 64 else { throw LoadedMachOImage.ReadError("Symbolic reference nesting limit exceeded") }
        var bytes: [UInt8] = []
        // Manglings contain binary payloads, including embedded zeroes. A
        // relative reference occupies its kind byte plus four payload bytes.
        // https://github.com/swiftlang/swift/blob/swift-6.2-RELEASE/docs/ABI/Mangling.rst#symbolic-references
        while bytes.count < 1 << 16 {
            let byte: UInt8 = try image.value(at: image.adding(Int64(bytes.count), to: address))
            if byte == 0 {
                let scalars = bytes.map { UnicodeScalar($0) }
                return try SwiftSymbol(scalars, isType: true) { displacement, payloadOffset in
                    let kind = bytes[payloadOffset - 1]
                    let payloadAddress = try image.adding(Int64(payloadOffset), to: address)
                    let target = try image.adding(Int64(displacement), to: payloadAddress)
                    switch kind {
                        case 1: return try contextType(at: target, depth: depth + 1)
                        case 2: return try contextType(at: image.value(at: target, as: UInt64.self), depth: depth + 1)
                            // Accessor-function references (kind 9) require execution
                            // or instruction analysis. This reader never invokes them.
                        default: throw LoadedMachOImage.ReadError("Unsupported symbolic reference kind: \(kind)")
                    }
                }
            }
            let length = (1...0x17).contains(byte) ? 5 : (0x18...0x1f).contains(byte) ? 9 : 1
            bytes += try image.bytes(at: image.adding(Int64(bytes.count), to: address), count: length)
        }
        throw LoadedMachOImage.ReadError("Unterminated symbolic mangling")
    }
}

fileprivate extension OpaqueTypeDescriptorReader {
    func contextType(at address: UInt64, depth: Int = 0) throws -> DemangledNode {
        guard depth < 64 else { throw LoadedMachOImage.ReadError("Context descriptor cycle or excessive nesting") }
        let flags: UInt32 = try image.value(at: address)
        guard flags & 0xff00 == 0 else { throw LoadedMachOImage.ReadError("Unsupported context descriptor version") }
        // ContextDescriptorKind and Target{Module,Protocol,Type}ContextDescriptor
        // share Flags + Parent. Named contexts have a relative Name at byte 8.
        // https://github.com/swiftlang/swift/blob/swift-6.2-RELEASE/include/swift/ABI/Metadata.h
        let kind = flags & 0x1f
        if kind == 0 { return .init(kind: .module, contents: .name(try image.name(at: image.relative(at: address + 8)))) }
        if kind == 1 { return try type(at: image.relative(at: address + 8), depth: depth + 1) }
        let nodeKind: DemangledNode.Kind
        switch kind {
            case 3: nodeKind = .protocol
            case 16: nodeKind = .class
            case 17: nodeKind = .structure
            case 18: nodeKind = .enum
            default: throw LoadedMachOImage.ReadError("Unsupported referenced context kind: \(kind)")
        }
        var parent = try contextType(at: image.relative(at: address + 4, indirectable: true), depth: depth + 1)
        if parent.kind == .type, parent.children.count == 1 { parent = parent.children[0] }
        let name = try image.name(at: image.relative(at: address + 8))
        return .init(kind: .type, children: [.init(kind: nodeKind, children: [parent, .init(kind: .identifier, contents: .name(name))])])
    }
    
    func parameterDepth(descriptor: UInt64, opaqueParameterCount: Int) throws -> Int {
        var counts: [Int] = []
        var parentField = descriptor + 4
        var visited = Set<UInt64>()
        while try image.value(at: parentField, as: Int32.self) != 0 {
            let parent = try image.relative(at: parentField, indirectable: true)
            guard visited.insert(parent).inserted, visited.count < 64 else { throw LoadedMachOImage.ReadError("Invalid parent descriptor chain") }
            let flags: UInt32 = try image.value(at: parent)
            if flags & 0x80 != 0 {
                let headerOffset: UInt64
                // Fixed descriptor sizes, followed (for nominal types) by the
                // 8-byte prefix of TargetTypeGenericContextDescriptorHeader.
                // https://github.com/swiftlang/swift/blob/swift-6.2-RELEASE/include/swift/ABI/Metadata.h
                switch flags & 0x1f {
                    case 1: headerOffset = 12
                    case 2, 4: headerOffset = 8
                    case 16: headerOffset = 44 + 8
                    case 17, 18: headerOffset = 28 + 8
                    default: throw LoadedMachOImage.ReadError("Unsupported generic parent descriptor")
                }
                counts.append(Int(try image.value(at: parent + headerOffset, as: UInt16.self)))
            }
            parentField = parent + 4
        }
        var depth = 0
        var previous = 0
        for count in counts.reversed() where count > previous {
            depth += 1
            previous = count
        }
        // An anonymous parent may already contain the function's parameters.
        // Count it once, and do not create a depth for nongeneric nested types
        // that repeat their parent's parameter count. Older descriptor shapes
        // can omit that parent; the opaque header still includes those params.
        // https://github.com/swiftlang/swift/blob/swift-6.2-RELEASE/stdlib/public/runtime/MetadataLookup.cpp
        let total = Int(try image.value(at: descriptor + 8, as: UInt16.self))
        guard total >= opaqueParameterCount, previous <= total - opaqueParameterCount else {
            throw LoadedMachOImage.ReadError("Opaque parameter count disagrees with its context")
        }
        if previous < total - opaqueParameterCount { depth += 1 }
        return depth
    }
    
    func opaqueOrdinals(in node: DemangledNode) -> Set<Int> {
        if node.kind == .opaqueReturnType {
            // Qr denotes ordinal 0; QR INDEX denotes INDEX + 1.
            // https://github.com/swiftlang/swift/blob/swift-6.2-RELEASE/docs/ABI/Mangling.rst
            if let child = node.children.first, case .index(let index) = child.contents,
               let ordinal = Int(exactly: index), ordinal < Int.max { return [ordinal + 1] }
            return [0]
        }
        // Inspect the declaration's type, excluding opaque types in its context.
        return Set(node.children.filter { node.kind == .type || $0.kind == .type || node.kind != .function && node.kind != .variable && node.kind != .subscript }
            .flatMap { opaqueOrdinals(in: $0) })
    }
    
    func rootParameter(_ node: DemangledNode, depth: Int) -> Int? {
        if node.kind == .type, node.children.count == 1 { return rootParameter(node.children[0], depth: depth) }
        guard node.kind == .dependentGenericParamType, node.children.count == 2,
              case .index(let parameterDepth) = node.children[0].contents, parameterDepth == UInt64(depth),
              case .index(let index) = node.children[1].contents else { return nil }
        return Int(exactly: index)
    }
    
    func parameters(in node: DemangledNode, atDepth depth: Int) -> Set<Int> {
        if let index = rootParameter(node, depth: depth) { return [index] }
        return Set(node.children.flatMap { parameters(in: $0, atDepth: depth) })
    }
}
