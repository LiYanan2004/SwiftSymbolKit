
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
