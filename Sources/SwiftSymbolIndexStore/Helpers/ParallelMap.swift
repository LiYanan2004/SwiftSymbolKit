/// One child task per input, with ordered results and cooperative cancellation.
enum ParallelMap {
    static func map<Input: Sendable, Output: Sendable>(
        _ inputs: [Input],
        transform: @escaping @Sendable (Input) async throws -> Output
    ) async throws -> [Output] {
        try Task.checkCancellation()
        return try await withThrowingTaskGroup(of: (Int, Output).self) { group in
            for (position, input) in inputs.enumerated() {
                try Task.checkCancellation()
                group.addTask {
                    try Task.checkCancellation()
                    return (position, try await transform(input))
                }
            }
            var results = [Output?](repeating: nil, count: inputs.count)
            for try await (position, output) in group {
                results[position] = .some(output)
            }
            try Task.checkCancellation()
            return results.map { $0! }
        }
    }
}
