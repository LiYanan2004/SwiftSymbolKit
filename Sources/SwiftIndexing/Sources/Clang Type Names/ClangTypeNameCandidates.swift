import Foundation

/// Decodes only main symbol graphs. Extension graphs must never supply the owner module.
struct ClangTypeNameCandidates {
    struct Candidate: Hashable {
        let swiftName: SwiftTypeName
        let requiredImport: String
        let clangUSR: String
        let declarationKind: String
    }

    private struct Graph: Decodable {
        struct Metadata: Decodable {
            struct Version: Decodable { let major: Int }
            let formatVersion: Version
        }
        struct Module: Decodable { let name: String }
        struct Symbol: Decodable {
            struct Identifier: Decodable { let precise: String }
            struct Kind: Decodable { let identifier: String }
            struct Fragment: Decodable { let kind: String; let spelling: String }
            let identifier: Identifier
            let kind: Kind
            let pathComponents: [String]
            let declarationFragments: [Fragment]?
        }
        let metadata: Metadata
        let module: Module
        let symbols: [Symbol]
    }

    static func read(_ data: Data, moduleName: String, requestedNames: Set<String>) throws -> [Candidate] {
        let graph = try JSONDecoder().decode(Graph.self, from: data)
        guard graph.metadata.formatVersion.major == 0, graph.module.name == moduleName else {
            throw ClangTypeNameResolver.ResolutionError.invalidSymbolGraph(moduleName)
        }
        let kinds: Set<String> = ["swift.class", "swift.struct", "swift.enum", "swift.protocol", "swift.typealias"]
        return graph.symbols.compactMap { symbol in
            guard kinds.contains(symbol.kind.identifier), symbol.identifier.precise.hasPrefix("c:"),
                  !symbol.pathComponents.isEmpty else { return nil }
            var names = Set<String>()
            let prefixes = ["c:@T@", "c:@S@", "c:@E@", "c:@U@", "c:objc(cs)", "c:objc(pl)"]
            for prefix in prefixes where symbol.identifier.precise.hasPrefix(prefix) {
                let name = String(symbol.identifier.precise.dropFirst(prefix.count))
                if isIdentifier(name) { names.insert(name) }
            }
            if symbol.kind.identifier == "swift.typealias" {
                names.formUnion((symbol.declarationFragments ?? [])
                    .filter { $0.kind == "typeIdentifier" }.map(\.spelling))
            }
            guard !names.isDisjoint(with: requestedNames) else { return nil }
            return Candidate(swiftName: .init(moduleName: moduleName, pathComponents: symbol.pathComponents),
                             requiredImport: moduleName, clangUSR: symbol.identifier.precise,
                             declarationKind: symbol.kind.identifier)
        }
    }

    /// The initial importer supports flat C/Objective-C identifiers and escaped Swift keywords.
    static func isIdentifier(_ value: String) -> Bool {
        let scalars = Array(value.unicodeScalars)
        let letters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_")
        let continuation = letters.union(CharacterSet(charactersIn: "0123456789"))
        return scalars.first.map(letters.contains) == true && scalars.dropFirst().allSatisfy(continuation.contains)
    }

    static func sourcePath(_ components: [String]) throws -> String {
        guard !components.isEmpty, components.allSatisfy(isIdentifier) else {
            throw ClangTypeNameResolver.ResolutionError.unsupportedName(components.joined(separator: "."))
        }
        return components.map { "`\($0)`" }.joined(separator: ".")
    }
}
