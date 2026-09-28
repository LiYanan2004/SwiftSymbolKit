//
//  SwiftSymbol.swift
//  SwiftSymbolKit
//
//  Created by Yanan Li on 2026/9/29.
//

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

extension SwiftSymbol {
    /// Parses a mangled Swift symbol or type into a symbol tree.
    ///
    /// - Parameters:
    ///   - mangledSymbol: The mangled symbol or type encoding.
    ///   - isType: Whether to parse a type encoding without a symbol prefix. Defaults to `false`.
    /// - Throws: `SwiftSymbolParseError` when parsing fails.
    public init(_ mangledSymbol: String, isType: Bool = false) throws {
        try self.init(mangledSymbol.unicodeScalars, isType: isType)
    }
    
    /// Parses Unicode scalars containing a mangled Swift symbol or type.
    ///
    /// - Parameters:
    ///   - mangledSymbol: The mangled symbol or type encoding.
    ///   - isType: Whether to parse a type encoding without a symbol prefix. Defaults to `false`.
    ///   - symbolicReferenceResolver: Resolves a signed relative reference and the scalar offset
    ///     of its four-byte payload. Binary payload bytes must be represented by scalars in
    ///     `0...255`; the preceding scalar identifies the reference kind.
    /// - Throws: `SwiftSymbolParseError` when parsing fails, or an error from the resolver.
    public init<Scalars: Collection>(
        _ mangledSymbol: Scalars,
        isType: Bool = false,
        symbolicReferenceResolver: ((Int32, Int) throws -> SwiftSymbol)? = nil
    ) throws where Scalars.Element == UnicodeScalar {
        var demangler = Demangler(scalars: mangledSymbol)
        demangler.symbolicReferenceResolver = symbolicReferenceResolver
        if isType {
            self = try demangler.demangleType()
            return
        }
        let mangledName = String(String.UnicodeScalarView(mangledSymbol))
        let isModernSymbol = getManglingPrefixLength(mangledSymbol) != 0 || mangledName.hasPrefix("async_Main") || mangledName.hasPrefix("_async_Main")
        self = try isModernSymbol ? demangler.demangleSymbol() : demangler.demangleSwift3TopLevelSymbol()
        originalMangling = mangledName
    }
}

extension SwiftSymbol {
    /// Demangles a symbol, returning the original name when parsing fails.
    ///
    /// Classification, when requested, also applies to names that cannot be parsed.
    public static func demangle(_ mangled: String, using options: SymbolPrintOptions = .default) -> String {
        guard let symbol = try? SwiftSymbol(mangled) else {
            let prefix = options.contains(.classify) ? SwiftSymbol.classificationPrefix(for: mangled, symbol: nil) : ""
            return prefix + mangled
        }
        let printed = symbol.print(using: options)
        return printed.isEmpty ? mangled : printed
    }
}

extension SwiftSymbol: CustomStringConvertible {
    /// Overridden method to allow simple printing with default options
    public var description: String {
        var printer = NodePrinter()
        _ = printer.print(self)
        return printer.target
    }
    
    /// Prints `SwiftSymbol`s to a String with the full set of printing options.
    ///
    /// - Parameter options: an option set containing the different `DemangleOptions` from the Swift project.
    /// - Returns: `self` printed to a string according to the specified options.
    public func print(using options: SymbolPrintOptions = .default) -> String {
        var printer = NodePrinter(options: options)
        _ = printer.print(self)
        if options.contains(.classify), let originalMangling {
            return Self.classificationPrefix(for: originalMangling, symbol: self) + printer.target
        }
        return printer.target
    }
}

fileprivate extension SwiftSymbol {
    static func classificationPrefix(for mangledName: String, symbol: SwiftSymbol?) -> String {
        var classifications: [String] = []
        if !mangledName.hasPrefix("async_Main") && !mangledName.hasPrefix("_async_Main") && !mangledName.hasPrefix("_T") && getManglingPrefixLength(mangledName.unicodeScalars) == 0 {
            classifications.append("N")
        }
        if isThunkSymbol(mangledName, symbol: symbol) {
            classifications.append("T:" + getThunkTarget(mangledName))
        }
        if let symbol, symbol.kind != .global || symbol.children.first.map({ usesNonSwiftCallingConvention($0.kind) }) == true {
            classifications.append("C")
        }
        return classifications.isEmpty ? "" : "{" + classifications.joined(separator: ",") + "} "
    }
    
    static func usesNonSwiftCallingConvention(_ kind: Kind) -> Bool {
        switch kind {
            case .typeMetadataAccessFunction, .valueWitness, .protocolWitnessTableAccessor,
                    .genericProtocolWitnessTableInstantiationFunction, .lazyProtocolWitnessTableAccessor,
                    .associatedTypeMetadataAccessor, .associatedTypeWitnessTableAccessor,
                    .baseWitnessTableAccessor, .objCAttribute:
                return true
            default:
                return false
        }
    }
    
    static func isThunkSymbol(_ mangledName: String, symbol: SwiftSymbol?) -> Bool {
        if getManglingPrefixLength(mangledName.unicodeScalars) != 0 {
            let name = Self.stripAsyncContinuation(Self.stripSuffix(mangledName))
            guard ["TA", "Ta", "To", "TO", "TR", "Tr", "TW", "fC"].contains(where: name.hasSuffix) else { return false }
            let parsedSymbol = name == mangledName ? symbol : try? SwiftSymbol(name)
            guard parsedSymbol?.kind == .global, let kind = parsedSymbol?.children.first?.kind else { return false }
            switch kind {
                case .objCAttribute, .nonObjCAttribute, .partialApplyObjCForwarder,
                        .partialApplyForwarder, .reabstractionThunkHelper, .reabstractionThunk,
                        .protocolWitness, .allocator:
                    return true
                default:
                    return false
            }
        }
        guard mangledName.hasPrefix("_T") else { return false }
        let remainder = mangledName.dropFirst(2)
        return ["To", "TO", "PA_", "PAo_"].contains(where: remainder.hasPrefix)
    }
    
    static func getThunkTarget(_ mangledName: String) -> String {
        if getManglingPrefixLength(mangledName.unicodeScalars) != 0 {
            guard Self.stripSuffix(mangledName) == mangledName else { return "" }
            let name = Self.stripAsyncContinuation(mangledName)
            if ["TR", "Tr", "TW"].contains(where: name.hasSuffix) { return "" }
            if name.hasSuffix("fC") { return String(name.dropLast()) + "c" }
            return String(name.dropLast(2))
        }
        let remainder = mangledName.dropFirst(2)
        if remainder.hasPrefix("PAo_") { return String(remainder.dropFirst(4)) }
        if remainder.hasPrefix("PA_") { return String(remainder.dropFirst(3)) }
        return "_T" + remainder.dropFirst(2)
    }
    
    static func stripSuffix(_ mangledName: String) -> String {
        guard mangledName.last?.isNumber == true, let dot = mangledName.firstIndex(of: ".") else { return mangledName }
        return String(mangledName[..<dot])
    }
    
    static func stripAsyncContinuation(_ mangledName: String) -> String {
        guard mangledName.hasSuffix("_") else { return mangledName }
        var name = String(mangledName.dropLast())
        while name.last?.isNumber == true { name.removeLast() }
        if name.hasSuffix("TQ") || name.hasSuffix("TY") { return String(name.dropLast(2)) }
        return mangledName
    }
}
