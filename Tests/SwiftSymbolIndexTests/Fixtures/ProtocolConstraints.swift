// Compiler-validated examples for protocol requirement extraction.
// Reproduce with swiftc -emit-library -enable-library-evolution -module-name Constraints,
// then nm -gUj; the exported names are stored in TestData/ProtocolConstraints.symbols.txt.
public protocol Foo {}
public protocol Boo<Element> { associatedtype Element }
public protocol Composition { associatedtype Model: Foo & Boo & AnyObject }
public protocol Dependent { associatedtype Model; associatedtype Foo: Boo<Model> }
public protocol Nested { associatedtype Model: Boo where Model.Element: Foo }
public protocol Inherited: Foo, Boo {}
public protocol ClassOnly { associatedtype Model: AnyObject }
public protocol Plain { associatedtype Model }
public protocol Deep {
    associatedtype Model: Boo where Model.Element: Boo, Model.Element.Element: Foo
}
public protocol Refined: Nested where Model.Element: Boo {}
