import Testing
@testable import SwiftDemangle

/// Semantics from swiftlang/swift at dd2b2263096c1da3103638de88b34460505cddb1.
struct UpstreamParityTests {
    enum PackFixture: CaseIterable {
        case emptyDirect, direct, emptyIndirect, indirect

        var input: String {
            switch self {
            case .emptyDirect: "yQSd"
            case .direct: "Si_SSQSd"
            case .emptyIndirect: "yQSi"
            case .indirect: "Si_SSQSi"
            }
        }

        var expectedKind: SwiftSymbol.Kind {
            switch self {
            case .emptyDirect, .direct: .silPackDirect
            case .emptyIndirect, .indirect: .silPackIndirect
            }
        }

        var expectedText: String {
            switch self {
            case .emptyDirect: "@direct Pack{}"
            case .direct: "@direct Pack{Swift.Int, Swift.String}"
            case .emptyIndirect: "@indirect Pack{}"
            case .indirect: "@indirect Pack{Swift.Int, Swift.String}"
            }
        }
    }

    enum PunycodeFixture: String, CaseIterable {
        case umlaut = "bcher_kva"
        case basic = "hello_"
        case nonbasic = "a"

        var expected: String {
            switch self {
            case .umlaut: "bücher"
            case .basic: "hello"
            case .nonbasic: "\u{80}"
            }
        }
    }

    @Test(arguments: PackFixture.allCases)
    func preservesSILPackConvention(fixture: PackFixture) throws {
        let symbol = try SwiftSymbol(fixture.input, isType: true)
        #expect(symbol.children.first?.kind == fixture.expectedKind)
        #expect(symbol.print() == fixture.expectedText)
    }

    @Test func printsGenericParametersFromTheirIndices() throws {
        #expect(genericParameterName(depth: 0, index: 26) == "AB")
        #expect(genericParameterName(depth: 3, index: 27) == "BB3")
        let parameter = try SwiftSymbol("qd1_26_", isType: true).children[0]
        #expect(parameter.text == nil)
        #expect(parameter.children.map(\.index) == [3, 27])
        #expect(parameter.print() == "BB3")
        let legacy = try SwiftSymbol("_Ttqd1_26_").children[0].children[0].children[0]
        #expect(legacy.text == nil)
        #expect(legacy.print() == "BB3")
    }

    @Test func argumentTupleHasNoIndexPayload() throws {
        let function = try SwiftSymbol("Siyc", isType: true).children[0]
        #expect(function.children[0].kind == .argumentTuple)
        #expect(function.children[0].index == nil)
    }

    @Test func placesYieldsAfterArguments() throws {
        let function = try SwiftSymbol("ySiXyyc", isType: true).children[0]
        #expect(function.children.map(\.kind) == [.argumentTuple, .yieldTypes, .returnType])
        #expect(throws: (any Error).self) { try SwiftSymbol("yySiXyc", isType: true) }
    }

    @Test func compoundAssociatedTypesHaveOneTypeWrapper() throws {
        let symbol = try SwiftSymbol("1A_1BQZ", isType: true)
        let member = symbol.children[0]
        #expect(member.kind == .dependentMemberType)
        #expect(member.children[0].children[0].kind == .dependentMemberType)
        #expect(member.children[0].children[0].children[0].children[0].kind == .dependentGenericParamType)
        #expect(symbol.print() == "A.A.B")
    }

    @Test func wrapsLegacyGenericConstraintsInTypeNodes() throws {
        let symbol = try SwiftSymbol("_TtuRxs8RunciblerFxwx5Mince")
        let signature = symbol.children[0].children[0].children[0].children[0]
        #expect(signature.children[1].children[0].kind == .type)
        #expect(signature.children[1].children[0].children[0].kind == .dependentGenericParamType)
    }

    @Test func relatedDeclarationKindIsAChild() throws {
        let declaration = try SwiftSymbol("$SSC9SomeErrorLeVD").children[0].children[0].children[0].children[1]
        #expect(declaration.kind == .relatedEntityDeclName)
        #expect(declaration.text == nil)
        #expect(declaration.children.map(\.text) == ["e", "SomeError"])
        #expect(declaration.print() == "related decl 'e' for SomeError")
    }

    @Test func valueWitnessHasIndexAndTypeChildren() throws {
        for input in ["$sSiwXX", "_TwXXSi"] {
            let witness = try SwiftSymbol(input).children[0]
            #expect(witness.index == nil)
            #expect(witness.children.map(\.kind) == [.index, .type])
            #expect(witness.children[0].index == 5)
            #expect(witness.print() == "destroyBuffer value witness for Swift.Int")
        }
        #expect(ValueWitnessKind.destroyArray.rawValue == 6)
    }

    @Test func negativeIntegerStoresSignedBitPattern() throws {
        let integer = try SwiftSymbol("$n3_", isType: true).children[0]
        #expect(integer.index == UInt64(bitPattern: -4))
        #expect(integer.print() == "-4")
        #expect(try SwiftSymbol("$n_", isType: true).print() == "0")
    }

    @Test func outlinedEnumOperationsConsumeTheirCaseIndex() throws {
        for input in ["$sSiWOi0_", "$sSiWOj0_"] {
            let symbol = try SwiftSymbol(input)
            #expect(symbol.children.count == 1)
            #expect(symbol.children[0].children.map(\.kind) == [.type, .number])
            #expect(symbol.children[0].children[1].index == 1)
        }
    }

    @Test func opaqueTypeKeepsOuterArgumentsAndConformancesSeparate() throws {
        let opaque = try SwiftSymbol("$s3foo3barQryFQOySi_SSSiSQHPyHCg_Qo_").children[0]
        #expect(opaque.kind == .opaqueType)
        #expect(opaque.children.map(\.kind) == [.opaqueReturnTypeOf, .index, .typeList, .typeList])
        #expect(opaque.children[2].children.map { $0.print() } == ["Swift.Int", "Swift.String"])
        #expect(opaque.children[3].children.map(\.kind) == [.retroactiveConformance])
    }

    @Test func symbolicContextsConsumeOnlyRemainingGenericArguments() throws {
        var demangler = Demangler(scalars: "".unicodeScalars)
        let reference = SwiftSymbol(kind: .typeSymbolicReference, contents: .index(42))
        let inner = SwiftSymbol(kind: .structure, children: [reference, SwiftSymbol(kind: .identifier, contents: .name("Inner"))])
        let arguments = [
            SwiftSymbol(kind: .typeList, child: try SwiftSymbol("Si", isType: true)),
            SwiftSymbol(kind: .typeList, child: try SwiftSymbol("SS", isType: true))
        ]
        let result = try demangler.demangleBoundGenericArgs(nominal: inner, array: arguments, index: 0)
        let parent = result.children[0].children[0].children[0]
        #expect(parent.kind == .boundGenericOtherNominalType)
        #expect(parent.children[1].children.count == 1)
        #expect(parent.children[1].children[0].print() == "Swift.String")
    }

    @Test func implementationSubstitutionsKeepConformanceLists() throws {
        for input in ["lySiSiSQHPyHCg_Isg_", "ySiSiSQHPyHCg_IIg_"] {
            let implementation = try SwiftSymbol(input, isType: true).children[0]
            let substitutions = implementation.children[0]
            #expect(substitutions.children.last?.kind == .typeList)
            #expect(substitutions.children.last?.children.first?.kind == .retroactiveConformance)
        }
        #expect(throws: (any Error).self) { try SwiftSymbol("ySi_SSIIg_", isType: true) }
    }

    @Test(arguments: PunycodeFixture.allCases)
    func decodesSwiftPunycode(fixture: PunycodeFixture) throws {
        #expect(try Punycode.decodePunycodeUTF8(fixture.rawValue) == fixture.expected)
    }

    @Test(arguments: ["z", "K", "{", "é_", "hello_!", String(repeating: "J", count: 40)])
    func rejectsInvalidPunycode(input: String) {
        #expect(throws: SwiftSymbolParseError.self) { try Punycode.decodePunycodeUTF8(input) }
    }

    @Test func identifierLengthCountsUTF8Bytes() throws {
        #expect(try SwiftSymbol("$s6中文1SV").print() == "中文.S")
        #expect(throws: (any Error).self) { try SwiftSymbol("$s2中文1SV") }
    }

    @Test(arguments: ["$sA!", "$sA.", "$syyXzC0", "$sSiWOi", "$sSiWOj", "_TtS18446744073709551614_", "_Tt18446744073709551615"])
    func rejectsMalformedInputs(input: String) {
        #expect(throws: (any Error).self) { try SwiftSymbol(input) }
    }

    @Test func builtinTupleCanBeAGenericContext() {
        #expect(SwiftSymbol.Kind.builtinTupleType.isContext)
        #expect(SwiftSymbol.Kind.builtinTupleType.isAnyGeneric)
    }

    @Test func optionalTupleDoesNotGainExtraParentheses() throws {
        #expect(try SwiftSymbol("ytSg", isType: true).print(using: [.synthesizeSugarOnTypes]) == "()?")
    }

    @Test func supportsPinnedLayoutConstraints() throws {
        let bitwise = try SwiftSymbol("RlzB", isType: true)
        #expect(bitwise.kind == .dependentGenericLayoutRequirement)
        #expect(bitwise.children[1].text == "B")
        let size = try SwiftSymbol("RlzS3_", isType: true)
        #expect(size.children[1].text == "S")
        #expect(size.children[2].index == 4)
    }

    @Test func supportsLegacyNoDerivativeTypes() throws {
        let type = try SwiftSymbol("_TtkSi").children[0].children[0].children[0]
        #expect(type.kind == .noDerivative)
        #expect(type.children[0].kind == .structure)
    }

    @Test func limitsPrinterRecursion() {
        var symbol = SwiftSymbol(kind: .identifier, contents: .name("Leaf"))
        for _ in 0..<770 { symbol = SwiftSymbol(kind: .type, child: symbol) }
        #expect(symbol.print() == "<<too complex>>")
    }
}
