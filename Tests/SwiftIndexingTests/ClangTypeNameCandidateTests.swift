import Foundation
@testable import SwiftIndexing
import Testing

struct ClangTypeNameCandidateTests {
    @Test func discoversUSRAndUnderlyingAliasNamesWithoutInferringABIKind() throws {
        let data = Data(#"""
        {"metadata":{"formatVersion":{"major":0}},"module":{"name":"Foundation"},"symbols":[
          {"identifier":{"precise":"c:@T@NSNotificationName"},"kind":{"identifier":"swift.struct"},"pathComponents":["NSNotification","Name"]},
          {"identifier":{"precise":"c:@T@NSRange"},"kind":{"identifier":"swift.typealias"},"pathComponents":["NSRange"],"declarationFragments":[{"kind":"typeIdentifier","spelling":"_NSRange"}]},
          {"identifier":{"precise":"c:objc(pl)NSObject"},"kind":{"identifier":"swift.protocol"},"pathComponents":["NSObjectProtocol"]},
          {"identifier":{"precise":"c:objc(cs)NSObject"},"kind":{"identifier":"swift.class"},"pathComponents":["NSObject"]},
          {"identifier":{"precise":"s:Fake"},"kind":{"identifier":"swift.struct"},"pathComponents":["NSNotificationName"]},
          {"identifier":{"precise":"c:@T@NSNotificationName@Nested"},"kind":{"identifier":"swift.struct"},"pathComponents":["Unsupported"]}
        ]}
        """#.utf8)
        let candidates = try ClangTypeNameCandidates.read(data, moduleName: "Foundation",
                                                          requestedNames: ["NSNotificationName", "_NSRange", "NSObject"])
        #expect(candidates.count == 4)
        #expect(candidates.contains { $0.swiftName.qualifiedName == "Foundation.NSNotification.Name" })
        #expect(candidates.contains { $0.swiftName.qualifiedName == "Foundation.NSRange" })
        #expect(throws: ClangTypeNameResolver.ResolutionError.self) {
            try ClangTypeNameCandidates.read(data, moduleName: "Other", requestedNames: ["NSObject"])
        }
    }
    
    @Test func rejectsUnsupportedFormatAndUnsafeSourceNames() throws {
        let data = Data(#"{"metadata":{"formatVersion":{"major":1}},"module":{"name":"Example"},"symbols":[]}"#.utf8)
        #expect(throws: ClangTypeNameResolver.ResolutionError.self) {
            try ClangTypeNameCandidates.read(data, moduleName: "Example", requestedNames: [])
        }
        #expect(try ClangTypeNameCandidates.sourcePath(["Example", "class"]) == "`Example`.`class`")
        #expect(throws: ClangTypeNameResolver.ResolutionError.self) {
            try ClangTypeNameCandidates.sourcePath(["Example", "Name\nimport Other"])
        }
    }
}
