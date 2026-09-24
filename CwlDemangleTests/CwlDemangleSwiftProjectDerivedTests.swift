//
//  CwlDemangleSwiftProjectDerivedTests.swift
//  CwlDemangleSwiftProjectDerivedTests
//
//  Created by Matt Gallagher on 2016/04/30.
//  Copyright © 2016 Matt Gallagher. All rights reserved.
//
//  Licensed under Apache License v2.0 with Runtime Library Exception
//
//  See http://swift.org/LICENSE.txt for license information
//  See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//

@testable import CwlDemangle
import Testing

struct CwlDemangleSwiftProjectDerivedTests {
    @Test(arguments: ManglingFixtures.validExamples)
    func demangles(example: ManglingFixtures.Example) throws {
        let parsed = try parseMangledSwiftSymbol(example.input)
        let result = parsed.print(using: SymbolPrintOptions.default.union(.synthesizeSugarOnTypes))
        #expect(result == example.output, "Failed to demangle \(example.input)")
    }

    @Test(arguments: ManglingFixtures.invalidExamples)
    func rejectsInvalidMangling(example: ManglingFixtures.Example) {
        #expect(throws: (any Error).self) {
            try parseMangledSwiftSymbol(example.input)
        }
    }

    @Test func testActorProtocolConformanceDescriptor() throws {
        let mangled = "$s7SwiftUI16_ImpossibleActorCScAAAMc"
        let symbol = try parseMangledSwiftSymbol(mangled)
        let result = symbol.print(using: SymbolPrintOptions.default.union(.synthesizeSugarOnTypes))
        #expect(result == "protocol conformance descriptor for SwiftUI._ImpossibleActor : Swift.Actor in SwiftUI")
    }
}
