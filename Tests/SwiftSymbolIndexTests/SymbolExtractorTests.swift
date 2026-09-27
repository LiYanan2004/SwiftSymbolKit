import SwiftDemangle
import SwiftSymbolIndexStore
import Testing

@Suite("Symbol tree extraction")
struct SymbolExtractorTests {
    private let extractor = SymbolExtractor()

    @Test func extractsCompilerGeneratedDeclarations() throws {
        for fixture in SymbolExtractionFixture.allCases {
            let extraction = try extractor.extract(fixture.input)
            #expect(extraction.diagnostics.isEmpty, "\(fixture)")
            #expect(extraction.declarations.map(\.name) == fixture.expectedNames, "\(fixture)")
            let declaration = try #require(extraction.declarations.last)
            #expect(declaration.kind == fixture.expectedKind)
            #expect(extraction.record.role == fixture.expectedRole)
            #expect(declaration.evidence == .direct)
            #expect(declaration.accessors == fixture.expectedAccessors)
            #expect(declaration.parameterLabels == fixture.expectedLabels)
            #expect(declaration.isStatic == (fixture == .staticMethod || fixture == .staticGetter))
            #expect(fixture.expectedSignatureKinds.isSubset(of: nodeKinds(in: declaration.signature)))
            #expect(extraction.record.mangledSymbol == fixture.input)
            #expect(extraction.record.declarationIDs == Set(extraction.declarations.map(\.id)))
            for ancestor in extraction.declarations.dropLast() {
                #expect(ancestor.evidence == .contextOnly)
                #expect(ancestor.mangledSymbols == [fixture.input])
            }
        }
    }

    @Test func preservesNestedContextAndAncestorIdentity() throws {
        let extraction = try extractor.extract(SymbolExtractionFixture.nestedMethod.input)
        let declarations = extraction.declarations
        #expect(declarations.count == 3)
        guard case .module(let moduleName) = declarations[0].context,
              case .declaration(let outerID) = declarations[1].context,
              case .declaration(let innerID) = declarations[2].context else {
            Issue.record("Expected a module, outer type and nested type context chain")
            return
        }
        #expect(moduleName == "Example")
        #expect(outerID == declarations[0].id)
        #expect(innerID == declarations[1].id)
        let metadata = try extractor.extract(SymbolExtractionFixture.nestedMetadata.input)
        #expect(metadata.declarations.map(\.id) == Array(declarations.prefix(2)).map(\.id))
    }

    @Test func normalizesRelatedSymbolsWithoutUsingPrintedNames() throws {
        for fixture in SymbolIdentityFixture.allCases {
            let identifiers = try fixture.input.map { input in
                let extraction = try extractor.extract(input)
                #expect(extraction.diagnostics.isEmpty, "\(input)")
                return try #require(extraction.declarations.last).id
            }
            #expect(Set(identifiers).count == 1, "\(fixture)")
        }
    }

    @Test func preservesSignatureNodesAndGenericScope() throws {
        let fixture = SymbolExtractionFixture.genericMethod
        let tree = try SwiftSymbol(fixture.input)
        let extraction = try extractor.extract(tree, mangledSymbol: fixture.input)
        let method = try #require(extraction.declarations.last)
        let originalSignature = try #require(tree.children.first?.children.last)
        #expect(method.signature?.description == originalSignature.description)
        #expect(method.genericSignature?.kind == .dependentGenericSignature)
        #expect(extraction.declarations.first?.genericSignature == nil)
        let parameterNodes = descendants(in: method.signature).filter { $0.kind == .dependentGenericParamType }
        let depths = parameterNodes.compactMap { node -> UInt64? in
            guard case .index(let depth) = node.children.first?.contents else { return nil }
            return depth
        }
        #expect(Set(depths) == [0, 1])
    }

    @Test func preservesConditionalExtensionOwnership() throws {
        let input = "$sSa7ExampleAA14SampleProtocolRzlE7inspectyyF"
        let extraction = try extractor.extract(input)
        #expect(extraction.declarations.map(\.name) == ["Array", "inspect"])
        let member = try #require(extraction.declarations.last)
        guard case .typeExtension(let context) = member.context,
              case .module(let ownerModule) = extraction.declarations[0].context else {
            Issue.record("Expected a foreign type and an extension context")
            return
        }
        #expect(context.moduleName == "Example")
        #expect(ownerModule == "Swift")
        #expect(context.extendedType == extraction.declarations[0].id)
        #expect(nodeKinds(in: context.genericSignature).contains(.dependentGenericConformanceRequirement))
        #expect(member.genericSignature == nil)
        #expect(extraction.declarations[0].genericSignature == nil)
    }

    @Test func extractsConditionalConformanceWithoutDeclaringReferencedTypes() throws {
        let input = "$s7Example3FooVyxGAA14SampleProtocolAASQRzlMc"
        let extraction = try extractor.extract(input)
        #expect(extraction.diagnostics.isEmpty)
        #expect(extraction.declarations.isEmpty)
        #expect(extraction.record.role == .descriptor)
        let conformance = try #require(extraction.conformances.first)
        #expect(conformance.moduleName == "Example")
        #expect(conformance.mangledSymbols == [input])
        #expect(conformance.protocolType.description == "Example.SampleProtocol")
        #expect(nodeKinds(in: conformance.conformingType).contains(.boundGenericStructure))
        #expect(nodeKinds(in: conformance.genericSignature).contains(.dependentGenericConformanceRequirement))
    }

    @Test func distinguishesOverloadsAndLinkerSpelling() throws {
        let integer = try extractor.extract("$s7Example6chooseyySiF")
        let string = try extractor.extract("$s7Example6chooseyySSF")
        let prefixed = try extractor.extract("_$s7Example6chooseyySiF")
        #expect(integer.declarations.last?.id != string.declarations.last?.id)
        #expect(integer.declarations.last?.id == prefixed.declarations.last?.id)
        #expect(integer.declarations.map(\.name) == ["choose"])
        #expect(string.declarations.map(\.name) == ["choose"])
        #expect(prefixed.record.mangledSymbol == "_$s7Example6chooseyySiF")
    }

    @Test func retainsUnsupportedSymbolsWithoutGuessingDeclarations() throws {
        for fixture in UnsupportedTreeFixture.allCases {
            let tree = try fixture.input
            let extraction = try extractor.extract(tree, mangledSymbol: "fixture")
            #expect(extraction.declarations.isEmpty, "\(fixture)")
            #expect(extraction.conformances.isEmpty)
            #expect(extraction.record.role == .unsupported)
            #expect(extraction.record.demangledSymbol.kind == tree.kind)
            #expect(extraction.diagnostics.count == 1)
            #expect(extraction.diagnostics.first?.kind == .unsupportedSymbol)
            #expect(extraction.diagnostics.first?.mangledSymbols == ["fixture"])
        }
    }

    @Test func rejectsMalformedSupportedNodes() throws {
        for fixture in MalformedTreeFixture.allCases {
            let tree = try fixture.input
            #expect(throws: SymbolExtractor.ExtractionError.self) {
                try extractor.extract(tree, mangledSymbol: "fixture")
            }
        }
    }

    @Test func propagatesDemanglingFailure() {
        #expect(throws: (any Error).self) {
            try extractor.extract("not a Swift mangled symbol")
        }
    }

    @Test func preservesDeclarationNamesAndDiscriminators() throws {
        var identifiers: Set<SymbolDeclaration.ID> = []
        for fixture in DeclarationNameFixture.allCases {
            var function = try SwiftSymbol(SymbolExtractionFixture.nestedMethod.input).children[0]
            function.children[1] = fixture.input
            let extraction = try extractor.extract(function, mangledSymbol: "fixture")
            let declaration = try #require(extraction.declarations.last)
            #expect(declaration.name == fixture.expectedName)
            #expect(declaration.nameNode?.kind == fixture.input.kind)
            identifiers.insert(declaration.id)
        }
        #expect(identifiers.count == DeclarationNameFixture.allCases.count)
    }

    @Test func distinguishesStaticMembersModulesAndParameterLabels() throws {
        let base = try SwiftSymbol(SymbolExtractionFixture.labeledFunction.input).children[0]
        var otherModule = base
        otherModule.children[0] = SwiftSymbol(kind: .module, contents: .name("Other"))
        var otherLabels = base
        otherLabels.children[2].children[1] = SwiftSymbol(kind: .identifier, contents: .name("last"))
        let staticFunction = SwiftSymbol(kind: .static, children: [base])
        let variants = [base, otherModule, otherLabels, staticFunction]
        let identifiers = try variants.map { tree in
            try #require(extractor.extract(tree, mangledSymbol: "fixture").declarations.last).id
        }
        #expect(Set(identifiers).count == variants.count)
    }

    @Test func preservesFunctionLocalContext() throws {
        let enclosingFunction = try SwiftSymbol(SymbolExtractionFixture.genericMethod.input).children[0]
        let localType = SwiftSymbol(kind: .structure, children: [
            enclosingFunction, SwiftSymbol(kind: .identifier, contents: .name("Local"))
        ])
        let extraction = try extractor.extract(localType, mangledSymbol: "fixture")
        #expect(extraction.declarations.map(\.name) == ["Foo", "transform", "Local"])
        let localDeclaration = try #require(extraction.declarations.last)
        guard case .declaration(let contextID) = localDeclaration.context else {
            Issue.record("Expected the enclosing function as declaration context")
            return
        }
        #expect(contextID == extraction.declarations[1].id)
        #expect(localDeclaration.genericSignature == nil)
        #expect(extraction.declarations[1].genericSignature != nil)
    }

    @Test func keepsExtensionRequirementsOutOfTypeIdentity() throws {
        let constrained = try extractor.extract("$s7Example3FooVAASQRzlE5helloyyF")
        let unconstrained = try extractor.extract("$s7Example3FooV5helloyyF")
        #expect(constrained.declarations.first?.id == unconstrained.declarations.first?.id)
        #expect(constrained.declarations.last?.id != unconstrained.declarations.last?.id)
        #expect(constrained.declarations.first?.genericSignature == nil)
    }

    @Test func supportsLegacyDeclarations() throws {
        let extraction = try extractor.extract("_TFC3foo3bar3basfT3zimCS_3zim_T_")
        #expect(extraction.diagnostics.isEmpty)
        #expect(extraction.declarations.map(\.name) == ["bar", "bas"])
        #expect(extraction.declarations.last?.kind == .function)
        #expect(extraction.declarations.last?.signature != nil)
    }
}

private func descendants(in symbol: SwiftSymbol?) -> [SwiftSymbol] {
    guard let symbol else { return [] }
    return [symbol] + symbol.children.flatMap { descendants(in: $0) }
}

private func nodeKinds(in symbol: SwiftSymbol?) -> Set<SwiftSymbol.Kind> {
    Set(descendants(in: symbol).map(\.kind))
}
