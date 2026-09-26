import Yams

/// The exported symbol sections of a YAML text-based dynamic library stub.
struct TextBasedStub: Decodable {
    let installName: String
    let exports: [SymbolSection]?
    let reexports: [SymbolSection]?

    struct SymbolSection: Decodable {
        let symbols: [String]?
        let weakDefinitionSymbols: [String]?
        let threadLocalSymbols: [String]?

        enum CodingKeys: String, CodingKey {
            case symbols
            case weakDefinitionSymbols = "weak-def-symbols"
            case threadLocalSymbols = "thread-local-symbols"
        }
    }

    enum CodingKeys: String, CodingKey {
        case installName = "install-name"
        case exports, reexports
    }

    init(yaml: String) throws {
        self = try YAMLDecoder().decode(Self.self, from: yaml)
    }

    /// Preserves linker spelling while removing duplicates across architecture sections.
    var swiftSymbols: [String] {
        let sections = (exports ?? []) + (reexports ?? [])
        let symbols = sections.flatMap {
            ($0.symbols ?? []) + ($0.weakDefinitionSymbols ?? []) + ($0.threadLocalSymbols ?? [])
        }
        let prefixes = ["_$s", "$s", "_$S", "$S", "_$e", "$e", "__T", "_T"]
        return Set(symbols.filter { symbol in
            prefixes.contains(where: symbol.hasPrefix)
        }).sorted()
    }
}
