/// Architecture, operating system and runtime environment used for source matching.
/// Deployment versions remain artifact metadata and do not affect this identity.
public struct IndexingTarget: Hashable, Sendable, Decodable {
    public enum Architecture: String, Hashable, Sendable, Decodable {
        case i386, x86_64, x86_64h
        case armv4t, armv5, armv6, armv7, armv7s, armv7k
        case armv6m, armv7m, armv7em
        case arm64, arm64e, arm64_32
        case arm64_x1 = "arm64.x1"
        case arm64e_x1 = "arm64e.x1"
    }

    public enum Platform: String, Hashable, Sendable, Decodable {
        case macOS = "macos"
        case iOS = "ios"
        case tvOS = "tvos"
        case watchOS = "watchos"
        case visionOS = "xros"
        case bridgeOS = "bridgeos"
        case driverKit = "driverkit"
    }

    public enum Environment: Hashable, Sendable {
        case native
        case simulator
        case macCatalyst
    }

    public enum ParsingError: Error, Equatable {
        case unsupportedTarget(String)
    }

    public let architecture: Architecture
    public let platform: Platform
    public let environment: Environment

    public init(architecture: Architecture, platform: Platform, environment: Environment = .native) {
        self.architecture = architecture
        self.platform = platform
        self.environment = environment
    }

    /// Accepts a TBD target or an Apple compiler target triple.
    public init(parsing value: String) throws {
        var components = value.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard components.count >= 2, let architecture = Architecture(rawValue: components.removeFirst()) else {
            throw ParsingError.unsupportedTarget(value)
        }
        if components.first == "apple" { components.removeFirst() }
        guard (1...2).contains(components.count) else { throw ParsingError.unsupportedTarget(value) }
        let operatingSystem = components.removeFirst()
        let name = String(operatingSystem.prefix { !$0.isNumber })
        let version = operatingSystem.dropFirst(name.count)
        guard version.isEmpty || version.split(separator: ".", omittingEmptySubsequences: false)
            .allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            throw ParsingError.unsupportedTarget(value)
        }
        let platform: Platform
        switch name {
        case "macos", "macosx", "osx": platform = .macOS
        case "maccatalyst": platform = .iOS
        default:
            guard let parsed = Platform(rawValue: name) else { throw ParsingError.unsupportedTarget(value) }
            platform = parsed
        }
        let environment: Environment
        switch components.first {
        case nil: environment = name == "maccatalyst" ? .macCatalyst : .native
        case "simulator" where [.iOS, .tvOS, .watchOS, .visionOS].contains(platform) && name != "maccatalyst":
            environment = .simulator
        case "macabi" where platform == .iOS && name != "maccatalyst":
            environment = .macCatalyst
        default: throw ParsingError.unsupportedTarget(value)
        }
        self.init(architecture: architecture, platform: platform, environment: environment)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        do {
            try self.init(parsing: value)
        } catch {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported target: \(value)")
        }
    }
}
