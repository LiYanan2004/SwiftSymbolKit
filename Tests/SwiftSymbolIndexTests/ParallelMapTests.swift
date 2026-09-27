import Testing
@testable import SwiftSymbolIndexStore

struct ParallelMapTests {
    @Test func preservesInputOrder() async throws {
        for count in [0, 1, 15, 16, 17, 257] {
            let inputs = Array(0..<count)
            let output = try await ParallelMap.map(inputs) {
                if $0.isMultiple(of: 3) { await Task.yield() }
                return $0 * 2
            }
            #expect(output == inputs.map { $0 * 2 })
        }
    }

    @Test func preservesOptionalResults() async throws {
        let output = try await ParallelMap.map([0, 1, 2]) { value -> Int? in
            value.isMultiple(of: 2) ? value : nil
        }
        #expect(output == [0, nil, 2])
    }

    @Test func propagatesCancellation() async throws {
        let task = Task {
            try await ParallelMap.map(Array(0..<64)) { value in
                try await Task.sleep(for: .seconds(60))
                return value
            }
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func renderingPropagatesCancellation() async throws {
        var store = SymbolIndexStore()
        try await store.merge(contentsOf: ParallelProcessingFixture.largeType.input)
        let index = store
        let task = Task {
            // Cancel from inside the task to make the entry condition deterministic.
            withUnsafeCurrentTask { $0?.cancel() }
            return try await SwiftInterfaceWriter(configuration: .init(moduleName: "Example", compilerVersion: "test"))
                .write(index)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
