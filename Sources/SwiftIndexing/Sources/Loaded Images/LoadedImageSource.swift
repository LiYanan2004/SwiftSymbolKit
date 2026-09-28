import SwiftDemangle

/// Supplements a single macOS target using the native loader, including images
/// supplied by the host dyld shared cache. Loading may run library initializers.
/// This source never adds export evidence or invokes metadata accessor functions.
public struct LoadedImageSource: IndexingSource {
    public let imagePath: String
    public let descriptorSymbols: [String]
    public let context: IndexingContext
    /// When supplied, select the loaded image's target and read only descriptor
    /// symbols covered by that target. The result reports the selected context.
    public let descriptorSymbolTargets: [String: Set<IndexingTarget>]?

    public init(imagePath: String, descriptorSymbols: [String], context: IndexingContext,
                descriptorSymbolTargets: [String: Set<IndexingTarget>]? = nil) {
        self.imagePath = imagePath
        self.descriptorSymbols = descriptorSymbols
        self.context = context
        self.descriptorSymbolTargets = descriptorSymbolTargets
    }

    public func read() async throws -> IndexingResult {
        guard context.isValid, descriptorSymbolTargets != nil || context.targets.count == 1 else {
            throw LoadedMachOImage.ReadError("Opaque recovery requires exactly one selected target")
        }
        let image = try LoadedMachOImage(path: imagePath)
        let selectedTargets: Set<IndexingTarget>
        if let descriptorSymbolTargets {
            guard Set(descriptorSymbolTargets.keys) == Set(descriptorSymbols),
                  descriptorSymbolTargets.values.allSatisfy({ !$0.isEmpty && $0.isSubset(of: context.targets) }) else {
                throw IndexingSourceError.invalidSymbolTargets
            }
            // dlsym locates an actual exported descriptor in the loaded image;
            // dladdr supplies its Mach-O header. dyld has already selected the
            // native slice, including arm64e shared-cache images under arm64.
            var selectedTarget: IndexingTarget?
            for symbol in Set(descriptorSymbols).sorted() {
                try Task.checkCancellation()
                guard let address = try? image.symbol(symbol) else { continue }
                selectedTarget = try image.identity(containing: address).target
                break
            }
            guard let selectedTarget else {
                throw LoadedMachOImage.ReadError("Cannot determine the loaded image target: no requested opaque descriptor was found")
            }
            guard context.targets.contains(selectedTarget) else {
                throw LoadedMachOImage.ReadError("The loaded image target is not covered by this TBD")
            }
            selectedTargets = [selectedTarget]
        } else { selectedTargets = context.targets }
        let reader = OpaqueTypeDescriptorReader(image: image)
        var observations: [SymbolObservation] = []
        var diagnostics: [SymbolDiagnostic] = []
        var identifiers = Set<String>()
        for symbol in Set(descriptorSymbols).sorted() {
            if let coverage = descriptorSymbolTargets?[symbol], coverage.isDisjoint(with: selectedTargets) { continue }
            try Task.checkCancellation()
            do {
                let tree = try SwiftSymbol(symbol)
                guard let descriptor = tree.children.first, descriptor.kind == .opaqueTypeDescriptor,
                      let owner = descriptor.children.first, owner.kind == .opaqueReturnTypeOf,
                      let declaration = owner.children.first else {
                    throw LoadedMachOImage.ReadError("Expected an opaque type descriptor symbol")
                }
                let address = try image.symbol(symbol)
                let identity = try image.identity(containing: address)
                guard selectedTargets == [identity.target] else {
                    throw LoadedMachOImage.ReadError("Loaded image target does not match the selected TBD target")
                }
                identifiers.insert(identity.identifier)
                let recovered = try reader.read(at: address, declaration: declaration)
                for type in recovered {
                    observations.append(.init(subject: .mangledSymbol(symbol), fact: .opaqueReturnType(type), location: symbol))
                    if type.underlyingType == nil {
                        diagnostics.append(.init(kind: .incompleteDeclaration,
                            message: "Opaque underlying type could not be resolved; accessor functions are not executed.",
                            mangledSymbols: [symbol], declarationID: nil, severity: .info))
                    }
                }
            } catch {
                diagnostics.append(.init(kind: .incompleteDeclaration, message: "Opaque recovery: \(error)",
                    mangledSymbols: [symbol], declarationID: nil, severity: .warning))
            }
        }
        let identifier = identifiers.sorted().joined(separator: ",")
        let source = SymbolEvidenceSource(kind: .loadedImage, location: imagePath,
            artifactIdentifier: identifier, lineageIdentifier: imagePath + ":" + identifier)
        // A loaded image's UUID identifies the host build. It cannot establish
        // that the runtime library was built from the caller's SDK version.
        let imageContext = IndexingContext(moduleName: context.moduleName, targets: selectedTargets)
        return IndexingResult(source: source, context: imageContext, diagnostics: diagnostics, observations: observations)
    }
}
