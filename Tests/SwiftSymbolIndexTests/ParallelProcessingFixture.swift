import Foundation

enum ParallelProcessingFixture: CaseIterable {
    case empty
    case relatedSymbols
    case multipleWindows
    case largeType
    case swiftData

    var input: [String] {
        get throws {
            switch self {
            case .empty: return []
            case .relatedSymbols:
                let symbols = SwiftInterfaceFixture.allCases.flatMap(\.input)
                    + LinkerSpellingFixture.allCases.flatMap(\.input)
                    + StorageMergeFixture.allCases.flatMap(\.input)
                    + ["$s7Example3FooVWOc", "$s7Example6ObjectCMo", "$s7Example6ObjectCMu"]
                return symbols + symbols.reversed()
            case .multipleWindows:
                return (0..<4105).map { position in
                    let name = "function\(position)"
                    return "$s7Example\(name.utf8.count)\(name)yyF"
                }
            case .largeType:
                return (0..<256).map { position in
                    let name = "method\(position)"
                    return "$s7Example3FooV\(name.utf8.count)\(name)yyF"
                }
            case .swiftData:
                let url = Bundle.module.url(forResource: "SwiftData.symbols", withExtension: "txt", subdirectory: "TestData")!
                return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
            }
        }
    }
}

enum ParallelFailureFixture: Int, CaseIterable {
    case first = 0
    case middle = 31
    case nextWindow = 4096

    var validPrefix: [String] {
        (0..<rawValue).map { position in
            let name = "function\(position)"
            return "$s7Example\(name.utf8.count)\(name)yyF"
        }
    }

    var invalidSymbol: String { "$sInvalid" }

    var input: [String] {
        validPrefix + [invalidSymbol, "$s7Example5lateryyF", "$sAnotherInvalid"]
    }
}
