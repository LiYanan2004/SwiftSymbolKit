/// Inputs and expected source fragments for interface reconstruction.
enum SwiftInterfaceFixture: CaseIterable {
    case declarations, generics, genericMethodOnly, nestedGenerics, typeSpellings, extensions, protocols, unsupported

    var moduleName: String { self == .protocols ? "Constraints" : "Example" }

    var input: [String] {
        switch self {
        case .declarations:
            return [SymbolExtractionFixture.nestedMethod.input, SymbolExtractionFixture.asyncMethod.input,
                    SymbolExtractionFixture.staticMethod.input, SymbolExtractionFixture.labeledFunction.input,
                    SymbolExtractionFixture.getter.input, SymbolExtractionFixture.setter.input,
                    SymbolExtractionFixture.enumCase.input, "$s7Example6ChoiceO5emptyyA2CmFWC",
                    "$s7Example6ObjectCACycfC", SymbolExtractionFixture.deinitializer.input,
                    "$s7Example5classyyF"]
        case .generics:
            return [SymbolExtractionFixture.initializer.input, SymbolExtractionFixture.genericMethod.input,
                    SymbolExtractionFixture.subscriptGetter.input, SymbolExtractionFixture.parameterPack.input,
                    SymbolExtractionFixture.typedThrows.input, SymbolExtractionFixture.ownership.input]
        case .extensions:
            return ["$s7Example3FooVAASQRzlE5helloyyF", "$s7Example3FooV5helloyyF",
                    "$sSa7ExampleAA14SampleProtocolRzlE7inspectyyF", "$sSa5OtherE7inspectyyF",
                    "$s7Example3FooVyxGAA14SampleProtocolAASQRzlMc"]
        case .nestedGenerics:
            return ["$s7Example5OuterV5InnerVyAEyx_qd__Gx_qd__tcfC",
                    "$s7Example5OuterV5InnerV9transformyqd0__qd0__x_qd__tXElF"]
        case .genericMethodOnly:
            return [SymbolExtractionFixture.genericMethod.input]
        case .typeSpellings:
            return ["$s7Example9metatypesyySim_AA14SampleProtocol_pXpAaC_pmtF",
                    "$s7Example8optionalyySSSicSg_SidtF"]
        case .protocols:
            return ProtocolRequirementFixture.allCases.map(\.input)
        case .unsupported:
            return [SymbolExtractionFixture.opaqueReturn.input, "$s7Example5hello5_fileLLyyF"]
        }
    }

    var expectedFragments: [String] {
        switch self {
        case .declarations:
            return ["public struct Foo {", "    public struct Boo {", "        public func hello() -> ()",
                    "public func hello(value: Swift.String) async throws -> Swift.Int",
                    "public static func hello(_: Swift.Int) -> Swift.String",
                    "public func labels(_: Swift.Int, second: Swift.Int) -> ()",
                    "public var computed: Swift.Int { get set }", "case value(_: Swift.Int)", "case empty",
                    "public init()", "    deinit", "public func `class`() -> ()"]
        case .generics:
            return ["public struct Foo<A> {", "public init(value: A)",
                    "public func transform<A1>(_: (A) -> A1) -> A1",
                    "public subscript(_: Swift.Int) -> A { get }",
                    "public func identity<each A>(_: repeat each A) -> (repeat each A)",
                    "public func checked() throws(Example.Failure) -> ()",
                    "public func transfer(_: __owned Swift.String) -> Swift.String"]
        case .extensions:
            return ["extension Example.Foo where A: Swift.Equatable {",
                    "extension Swift.Array where A: Example.SampleProtocol {",
                    "extension Example.Foo: Example.SampleProtocol where A: Swift.Equatable {"]
        case .nestedGenerics:
            return ["public struct Outer<A> {", "public struct Inner<A1> {",
                    "public init(_: A, _: A1)", "public func transform<A2>(_: (A, A1) -> A2) -> A2"]
        case .genericMethodOnly:
            return ["public struct Foo<A> {", "public func transform<A1>(_: (A) -> A1) -> A1"]
        case .typeSpellings:
            return ["public func metatypes(_: (Swift.Int).Type, _: (Example.SampleProtocol).Type, _: (Example.SampleProtocol).Protocol) -> ()",
                    "public func optional(_: Swift.Optional<(Swift.Int) -> Swift.String>, _: Swift.Int...) -> ()"]
        case .protocols:
            return ["public protocol Inherited: Constraints.Foo {",
                    "public protocol Composition where Self.Model: Constraints.Foo {",
                    "associatedtype Model", "Self.Model.Element.Element: Constraints.Foo",
                    "Self.Model.Element: Constraints.Boo"]
        case .unsupported: return ["public func opaque() -> some", "public func hello() -> ()"]
        }
    }

    var excludedFragments: [String] {
        switch self {
        case .declarations: return ["public case", "public deinit", " = "]
        case .generics, .genericMethodOnly, .nestedGenerics, .typeSpellings: return ["<A><", "τ_"]
        case .extensions: return ["public struct Array", "public extension"]
        case .protocols: return ["public associatedtype"]
        case .unsupported: return ["some Any"]
        }
    }
}
