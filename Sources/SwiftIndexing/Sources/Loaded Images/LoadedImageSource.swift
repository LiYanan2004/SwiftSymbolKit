import Foundation
import MachO
import MachOKit
import SwiftDemangle

/// Supplements a target from an explicit Mach-O file or the current system shared cache.
/// This source never adds export evidence or invokes metadata accessor functions.
public struct LoadedImageSource: IndexingSource {
    public let imagePath: String?
    public let imageInstallName: String?
    public let descriptorSymbols: [String]
    public let enumDescriptorSymbols: [String]
    public let context: IndexingContext
    /// Coverage for every opaque and enum descriptor supplied to this reader.
    /// Selects the image's target and reports that selected context in the result.
    public let descriptorSymbolTargets: [String: Set<CompilerTarget>]?
    
    public init(
        imagePath: String? = nil,
        imageInstallName: String? = nil,
        descriptorSymbols: [String],
        context: IndexingContext,
        descriptorSymbolTargets: [String: Set<CompilerTarget>]? = nil,
        enumDescriptorSymbols: [String] = []
    ) {
        self.imagePath = imagePath
        self.imageInstallName = imageInstallName
        self.descriptorSymbols = descriptorSymbols
        self.context = context
        self.descriptorSymbolTargets = descriptorSymbolTargets
        self.enumDescriptorSymbols = enumDescriptorSymbols
    }
    
    public func read() async throws -> IndexingResult {
        guard context.isValid, descriptorSymbolTargets != nil || context.targets.count == 1 else {
            throw ReadError.invalidTargetSelection
        }
        if let descriptorSymbolTargets {
            guard Set(descriptorSymbolTargets.keys) == Set(descriptorSymbols + enumDescriptorSymbols),
                  descriptorSymbolTargets.values.allSatisfy({ !$0.isEmpty && $0.isSubset(of: context.targets) }) else {
                throw IndexingSourceError.invalidSymbolTargets
            }
        }
        let reader: OpaqueTypeDescriptorReader
        let identity: (target: CompilerTarget, identifier: String)
        let symbol: (String) throws -> UInt64
        let location: String
        if let imagePath {
            let url = URL(fileURLWithPath: imagePath)
            let files: [MachOFile]
            switch try MachOKit.loadFromFile(url: url) {
                case let .machO(file):
                    files = [file]
                case let .fat(file):
                    files = try file.machOFiles()
            }
            let candidates = try files.map { (file: $0, identity: try Self.identity(of: $0)) }
            let matching = candidates.filter { context.targets.contains($0.identity.target) }
            guard matching.count <= 1 else { throw ReadError.ambiguousFileTargets }
            guard let selected = matching.first ?? (candidates.count == 1 ? candidates.first : nil) else {
                throw ReadError.noMatchingFileTarget
            }
            identity = selected.identity
            let metadata = try MachOFileMetadata(file: selected.file)
            reader = OpaqueTypeDescriptorReader(
                machO: selected.file,
                readBytes: metadata.bytes,
                resolvePointer: metadata.pointer
            )
            symbol = metadata.symbol
            location = imagePath
        } else {
            guard let imageInstallName else { throw ReadError.missingImageInstallName }
            guard let cache = DyldCacheLoaded.current else { throw ReadError.sharedCacheUnavailable }
            let images = Array(cache.machOImages())
            guard let image = images.first(where: { $0.path == imageInstallName }) else {
                throw ReadError.imageNotInSharedCache(imageInstallName)
            }
            identity = try Self.identity(of: image)
            reader = OpaqueTypeDescriptorReader(machO: image)
            let resolver = MachOImageSymbolResolver(images: images)
            symbol = { try resolver.address(of: $0, in: image) }
            location = imageInstallName
        }
        let selectedTargets: Set<CompilerTarget>
        if descriptorSymbolTargets != nil {
            guard context.targets.contains(identity.target) else {
                throw ReadError.platformOrArchMismatch(expect: context.targets, real: identity.target)
            }
            selectedTargets = [identity.target]
        } else {
            selectedTargets = context.targets
        }
        var recoveredTypes: [(symbol: String, type: OpaqueReturnType)] = []
        var diagnostics: [SymbolDiagnostic] = []
        var identifiers = Set<String>()
        for descriptorSymbol in Set(descriptorSymbols).sorted() {
            if let coverage = descriptorSymbolTargets?[descriptorSymbol], coverage.isDisjoint(with: selectedTargets) { continue }
            try Task.checkCancellation()
            do {
                let tree = try SwiftSymbol(descriptorSymbol)
                guard let descriptor = tree.children.first, descriptor.kind == .opaqueTypeDescriptor,
                      let owner = descriptor.children.first, owner.kind == .opaqueReturnTypeOf,
                      let declaration = owner.children.first else {
                    throw ReadError.invalidDescriptorSymbol
                }
                let address = try symbol(descriptorSymbol)
                guard selectedTargets == [identity.target] else {
                    throw ReadError.platformOrArchMismatch(expect: selectedTargets, real: identity.target)
                }
                identifiers.insert(identity.identifier)
                let recovered = try reader.read(at: address, declaration: declaration)
                for type in recovered {
                    recoveredTypes.append((symbol: descriptorSymbol, type: type))
                    if type.underlyingType == nil {
                        diagnostics.append(.init(kind: .incompleteDeclaration,
                                                 message: "Opaque underlying type could not be resolved; accessor functions are not executed.",
                                                 mangledSymbols: [descriptorSymbol], declarationID: nil, severity: .info))
                    }
                }
            } catch {
                diagnostics.append(.init(kind: .incompleteDeclaration, message: "Opaque recovery: \(error)",
                                         mangledSymbols: [descriptorSymbol], declarationID: nil, severity: .warning))
            }
        }
        let identifier = identifiers.sorted().joined(separator: ",")
        var enumRecords: [(owner: SymbolDeclaration.ID, name: String, isIndirect: Bool, location: String)] = []
        for descriptorSymbol in Set(enumDescriptorSymbols).sorted() {
            if let coverage = descriptorSymbolTargets?[descriptorSymbol], coverage.isDisjoint(with: selectedTargets) { continue }
            try Task.checkCancellation()
            do {
                guard selectedTargets == [identity.target] else {
                    throw ReadError.platformOrArchMismatch(expect: selectedTargets, real: identity.target)
                }
                let tree = try SwiftSymbol(descriptorSymbol)
                guard let descriptor = tree.children.first, descriptor.kind == .nominalTypeDescriptor,
                      let type = descriptor.children.first,
                      let enumeration = type.kind == .type ? type.children.first : type, enumeration.kind == .enum else {
                    throw EnumCaseMetadataReader.ReadError.invalidEnumDescriptor
                }
                let records = try EnumCaseMetadataReader(metadata: reader).read(at: symbol(descriptorSymbol), enumeration: enumeration)
                let owner = SymbolDeclaration.ID(structuralKey: enumeration.declarationKey)
                enumRecords += records.map { (owner, $0.name, $0.isIndirect, descriptorSymbol + ":" + $0.name) }
            } catch is CancellationError { throw CancellationError() }
            catch {
                diagnostics.append(.init(kind: .incompleteDeclaration, message: "Enum case metadata recovery: \(error)",
                                         mangledSymbols: [descriptorSymbol], declarationID: nil, severity: .warning))
            }
        }
        let source = SymbolEvidenceSource(kind: .loadedImage, location: location,
                                          artifactIdentifier: enumRecords.isEmpty ? identifier : identity.identifier,
                                          lineageIdentifier: location + ":" + identity.identifier)
        // A loaded image's UUID identifies the host build. It cannot establish
        // that the runtime library was built from the caller's SDK version.
        let imageContext = IndexingContext(moduleName: context.moduleName, targets: selectedTargets)
        let evidence = recoveredTypes.map {
            SymbolEvidence(source: source, subject: .mangledSymbol($0.symbol),
                           fact: .opaqueReturnType($0.type), location: $0.symbol)
        } + enumRecords.map {
            SymbolEvidence(source: source, subject: .enumCase(owner: $0.owner, name: $0.name),
                           fact: .enumCaseIndirectStorage(isIndirect: $0.isIndirect), location: $0.location)
        }
        return IndexingResult(source: source, context: imageContext, diagnostics: diagnostics, evidence: evidence)
    }
    
    enum ReadError: Error, CustomStringConvertible {
        case missingImageInstallName
        case sharedCacheUnavailable
        case imageNotInSharedCache(String)
        case ambiguousFileTargets
        case noMatchingFileTarget
        case unsupportedSymbol(String)
        case invalidTargetSelection
        case invalidDescriptorSymbol
        case unsupportedImageFormat
        case invalidImageMetadata
        case missingExportedDescriptor(String)
        case unsupportedArchitecture(CPU)
        case platformOrArchMismatch(expect: Set<CompilerTarget>, real: CompilerTarget)
        
        var description: String {
            func targetName(_ target: CompilerTarget) -> String {
                let name = "\(target.architecture.rawValue)-\(target.platform.rawValue)"
                switch target.environment {
                    case .native:
                        return name
                    case .simulator:
                        return name + "-simulator"
                    case .macCatalyst:
                        return name + "-macabi"
                }
            }
            switch self {
                case .missingImageInstallName:
                    return "A TBD install name is required to select an image from the shared cache"
                case .sharedCacheUnavailable:
                    return "The current system dyld shared cache is unavailable"
                case let .imageNotInSharedCache(name):
                    return "Image not found in the current system dyld shared cache: \(name)"
                case .ambiguousFileTargets:
                    return "Multiple Mach-O slices match the selected TBD targets; select a single target"
                case .noMatchingFileTarget:
                    return "No Mach-O slice matches the selected TBD targets"
                case let .unsupportedSymbol(name):
                    return "Unsupported or cyclic exported symbol reference: \(name)"
                case .invalidTargetSelection:
                    return "Opaque recovery requires exactly one selected target"
                case .invalidDescriptorSymbol:
                    return "Expected an opaque type descriptor symbol"
                case .unsupportedImageFormat:
                    return "Only little-endian 64-bit Mach-O images are supported"
                case .invalidImageMetadata:
                    return "Opaque recovery requires a supported platform and an LC_UUID"
                case let .missingExportedDescriptor(name):
                    return "Missing exported descriptor: \(name)"
                case let .unsupportedArchitecture(cpu):
                    return "Unsupported image architecture: \(cpu)"
                case let .platformOrArchMismatch(expect, real):
                    let targets = expect.map(targetName).sorted().joined(separator: ", ")
                    return "Loaded MachO Image mismatch: expected [\(targets)], but get \(targetName(real))"
            }
        }
    }
}

extension LoadedImageSource {
    static func identity(of machO: some MachORepresentable) throws -> (target: CompilerTarget, identifier: String) {
        guard machO.header.magic == .magic64 else { throw ReadError.unsupportedImageFormat }
        let architecture = try architecture(for: machO.header)
        let commands = machO.loadCommands
        let platform = commands.info(of: LoadCommand.buildVersion)?.platform
        ?? (commands.info(of: LoadCommand.versionMinMacosx) != nil ? .macOS : nil)
        guard let platform, let uuid = commands.info(of: LoadCommand.uuid)?.uuid else {
            throw ReadError.invalidImageMetadata
        }
        let identifier = uuid.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let targetPlatform: CompilerTarget.Platform
        var environment = CompilerTarget.Environment.native
        switch platform {
            case .macOS:
                targetPlatform = .macOS
            case .iOS:
                targetPlatform = .iOS
            case .tvOS:
                targetPlatform = .tvOS
            case .watchOS:
                targetPlatform = .watchOS
            case .visionOS:
                targetPlatform = .visionOS
            case .bridgeOS:
                targetPlatform = .bridgeOS
            case .driverKit:
                targetPlatform = .driverKit
            case .macCatalyst:
                targetPlatform = .iOS
                environment = .macCatalyst
            case .iOSSimulator:
                targetPlatform = .iOS
                environment = .simulator
            case .tvOSSimulator:
                targetPlatform = .tvOS
                environment = .simulator
            case .watchOSSimulator:
                targetPlatform = .watchOS
                environment = .simulator
            case .visionOSSimulator:
                targetPlatform = .visionOS
                environment = .simulator
            default:
                throw ReadError.invalidImageMetadata
        }
        return (.init(architecture: architecture, platform: targetPlatform, environment: environment), identifier)
    }
    
    static func architecture(for header: MachHeader) throws -> CompilerTarget.Architecture {
        // MachOKit decodes CPU subtypes and their capability bits. Only target
        // spelling and the architectures supported by this reader live here.
        switch (header.cpuType, header.cpuSubType) {
            case (.arm64, .arm64(.arm64_all)), (.arm64, .arm64(.arm64_v8)):
                return .arm64
            case (.arm64, .arm64(.arm64e)):
                return .arm64e
            case (.arm64, .arm64(.arm64_x1)):
                return .arm64_x1
            case (.arm64, .arm64(.arm64e_x1)):
                return .arm64e_x1
            case (.x86_64, .x86(.x86_64_all)):
                return .x86_64
            case (.x86_64, .x86(.x86_64_h)):
                return .x86_64h
            default:
                throw ReadError.unsupportedArchitecture(header.cpu)
        }
    }
}
