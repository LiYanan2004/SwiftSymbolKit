/// Reads supplemental metadata from an image in a dyld shared cache.
///
/// Integration TODO:
/// - Consolidate current-system cache selection from `LoadedImageSource` here,
///   alongside the explicit cache-file input represented by `location`.
/// - Reuse `MachOImageSymbolResolver` and `OpaqueTypeDescriptorReader` for loaded
///   cache images; retain a separate input for standalone Mach-O files.
/// - Emit `.dyldSharedCache` evidence with the image target and UUID, and route
///   opaque facts through `SymbolIndexStore.mergeOpaqueReturnTypes`.
/// - Preserve requested-information filtering and per-symbol target coverage.
public struct DyldSharedCacheSource: IndexingSource {
    public let requestedInformation: Set<SupplementalInformation>
    public let location: String
    public let imageInstallName: String

    public init(location: String, imageInstallName: String, requestedInformation: Set<SupplementalInformation>) {
        self.location = location
        self.imageInstallName = imageInstallName
        self.requestedInformation = requestedInformation
    }

    public func read() async throws -> IndexingResult {
        fatalError("TODO: Read the requested runtime information and related observations with cache/image context.")
    }
}
