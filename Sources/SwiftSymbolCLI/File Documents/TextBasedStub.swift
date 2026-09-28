import SwiftIndexing
import Yams

typealias TBD = TextBasedStub

/// A YAML text-based dynamic library stub, retaining each symbol section's coverage.
struct TextBasedStub: Decodable {
    let installName: String
    let targets: Set<IndexingTarget>
    let exports: [SymbolSection]?
    let reexports: [SymbolSection]?

    struct SymbolSection: Decodable {
        let targets: Set<IndexingTarget>
        let symbols: [String]?
        let weakDefinitionSymbols: [String]?
        let threadLocalSymbols: [String]?

        enum CodingKeys: String, CodingKey {
            case targets, archs, symbols
            case weakDefinitionSymbols = "weak-def-symbols"
            case weakSymbols = "weak-symbols"
            case threadLocalSymbols = "thread-local-symbols"
        }

        init(from decoder: any Decoder) throws {
            try self.init(from: decoder, legacyPlatform: nil)
        }

        fileprivate init(from decoder: any Decoder, legacyPlatform: LegacyPlatform?) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let decodedTargets = try container.decodeIfPresent(Set<IndexingTarget>.self, forKey: .targets) {
                targets = decodedTargets
            } else if let legacyPlatform {
                let architectures = try container.decode([IndexingTarget.Architecture].self, forKey: .archs)
                targets = try TextBasedStub.legacyTargets(architectures, platform: legacyPlatform)
            } else {
                throw DecodingError.keyNotFound(CodingKeys.targets, .init(codingPath: decoder.codingPath,
                    debugDescription: "A symbol section requires target coverage."))
            }
            symbols = try container.decodeIfPresent([String].self, forKey: .symbols)
            weakDefinitionSymbols = try container.decodeIfPresent([String].self, forKey: .weakSymbols)
                ?? container.decodeIfPresent([String].self, forKey: .weakDefinitionSymbols)
            threadLocalSymbols = try container.decodeIfPresent([String].self, forKey: .threadLocalSymbols)
        }
    }

    enum CodingKeys: String, CodingKey {
        case installName = "install-name"
        case targets, archs, platform, exports, reexports
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        installName = try container.decode(String.self, forKey: .installName)
        let legacyPlatform = try container.decodeIfPresent(LegacyPlatform.self, forKey: .platform)
        if let decodedTargets = try container.decodeIfPresent(Set<IndexingTarget>.self, forKey: .targets) {
            targets = decodedTargets
        } else {
            let architectures = try container.decode([IndexingTarget.Architecture].self, forKey: .archs)
            targets = try Self.legacyTargets(architectures, platform: container.decode(LegacyPlatform.self, forKey: .platform))
        }
        func sections(for key: CodingKeys) throws -> [SymbolSection]? {
            guard container.contains(key) else { return nil }
            var sections = try container.nestedUnkeyedContainer(forKey: key)
            var result: [SymbolSection] = []
            while !sections.isAtEnd {
                result.append(try SymbolSection(from: sections.superDecoder(), legacyPlatform: legacyPlatform))
            }
            return result
        }
        exports = try sections(for: .exports)
        reexports = try sections(for: .reexports)
        guard !targets.isEmpty,
              ((exports ?? []) + (reexports ?? [])).allSatisfy({ !$0.targets.isEmpty && $0.targets.isSubset(of: targets) }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Section targets must be nonempty subsets of the file targets."))
        }
    }

    init(yaml: String) throws {
        self = try YAMLDecoder().decode(Self.self, from: yaml)
    }

    /// Preserves linker spelling and unions coverage when a symbol occurs in multiple sections.
    var swiftSymbolTargets: [String: Set<IndexingTarget>] {
        var result: [String: Set<IndexingTarget>] = [:]
        let prefixes = ["_$s", "$s", "_$S", "$S", "_$e", "$e", "__T", "_T"]
        for section in (exports ?? []) + (reexports ?? []) {
            let symbols = (section.symbols ?? []) + (section.weakDefinitionSymbols ?? []) + (section.threadLocalSymbols ?? [])
            for symbol in symbols where prefixes.contains(where: symbol.hasPrefix) {
                result[symbol, default: []].formUnion(section.targets)
            }
        }
        return result
    }

    var swiftSymbols: [String] { swiftSymbolTargets.keys.sorted() }

    fileprivate enum LegacyPlatform: String, Decodable {
        case macOS = "macos"
        case iOS = "ios"
        case tvOS = "tvos"
        case watchOS = "watchos"
        case bridgeOS = "bridgeos"
        case macCatalyst = "maccatalyst"

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            switch value {
            case "macosx", "osx": self = .macOS
            case "iosmac": self = .macCatalyst
            default:
                guard let platform = Self(rawValue: value) else {
                    throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported platform: \(value)")
                }
                self = platform
            }
        }
    }

    private static func legacyTargets(_ architectures: [IndexingTarget.Architecture], platform: LegacyPlatform) throws -> Set<IndexingTarget> {
        try Set(architectures.map { architecture in
            let target = try IndexingTarget(parsing: "\(architecture.rawValue)-\(platform.rawValue)")
            if [.i386, .x86_64, .x86_64h].contains(architecture),
               [.iOS, .tvOS, .watchOS].contains(target.platform), target.environment == .native {
                return IndexingTarget(architecture: architecture, platform: target.platform, environment: .simulator)
            }
            return target
        })
    }
}
