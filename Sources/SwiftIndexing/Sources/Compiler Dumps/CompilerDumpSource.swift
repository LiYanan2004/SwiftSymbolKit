
/// Reads captured output; the caller controls tool execution and records its invocation.
public struct CompilerDumpSource: IndexingSource {
    public let requestedInformation: Set<SupplementalInformation>
    public let location: String
    public let producer: String

    public init(location: String, producer: String, requestedInformation: Set<SupplementalInformation>) {
        self.location = location
        self.producer = producer
        self.requestedInformation = requestedInformation
    }

    public func read() async throws -> IndexingResult {
        fatalError("TODO: Decode the requested dump information and related observations with invocation context.")
    }
}
