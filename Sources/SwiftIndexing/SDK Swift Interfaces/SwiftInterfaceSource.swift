
public struct SwiftInterfaceSource: IndexingSource {
    public let requestedInformation: Set<SupplementalInformation>
    public let location: String

    public init(location: String, requestedInformation: Set<SupplementalInformation>) {
        self.location = location
        self.requestedInformation = requestedInformation
    }

    public func read() async throws -> IndexingResult {
        fatalError("TODO: Parse the requested interface information and related observations with artifact context.")
    }
}
