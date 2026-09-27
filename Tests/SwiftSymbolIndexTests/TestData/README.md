# SwiftData symbol fixture

`SwiftData.symbols.txt` contains the 1,588 unique `_$s`-prefixed symbols from the macOS 26.2 SDK's `SwiftData.framework/Versions/A/SwiftData.tbd`, sorted lexicographically. The source file was supplied with the merge implementation request.

The fixture includes accessors, metadata, descriptors, dispatch thunks, associated types, conditional conformances, and unsupported auxiliary symbols. It is checked in so tests run independently of the installed Xcode SDK. Expected counts and selected declaration facts are asserted in `SymbolStoreTests.mergesSwiftDataExports`.

## Protocol requirement fixture

`ProtocolConstraints.symbols.txt` was generated from `Fixtures/ProtocolConstraints.swift` with the installed Xcode Swift compiler:

```sh
swiftc -emit-library -enable-library-evolution -module-name Constraints \
  Tests/SwiftSymbolIndexTests/Fixtures/ProtocolConstraints.swift -o /tmp/libConstraints.dylib
nm -gUj /tmp/libConstraints.dylib
```

It covers protocol inheritance, protocol compositions, primary associated type syntax, paths up to three components, and inherited associated types. `Refined.Model` belongs to `Nested`; path qualifiers preserve that ownership.

The source compiles both `associatedtype Model: Foo & Boo & AnyObject` and `associatedtype Foo: Boo<Model>` (where `Boo<Element>` declares its primary associated type). Compiling the same module after removing the `AnyObject` constraints and changing `Foo: Boo<Model>` to `Foo: Boo` produces an identical exported symbol list. Thus these descriptors expose protocol conformance requirements but do not recover the class layout constraint or `Foo.Element == Model`. The index retains observed requirements without claiming completeness; future interface generation needs additional evidence for omitted requirements and primary associated type declarations.

## Parameter pack fixture

`ParameterPacks.symbols.txt` contains exports generated from `Fixtures/ParameterPacks.swift` with Apple Swift 6.2.4 using `swiftc -emit-library -enable-library-evolution -module-name PackFixtures`, followed by `nm -gUj`. It covers empty and concrete packs, mixed scalar/pack arguments, pack properties and initializers, and conditional protocol conformance. `ParameterPackTests` checks rendering and order independence.

## Addressor validation source

`Fixtures/Addressors.swift` compiles with Apple Swift 6.2.4 using `swiftc -emit-library -emit-module-interface-path Addressors.swiftinterface -enable-library-evolution -module-name Addressors`. The compiler preserves `unsafeAddress` and `nonmutating unsafeMutableAddress` in its interface. Mangled addressor symbols identify readable/mutable address access but do not encode the mutating modifier; reconstruction retains addressor spelling and diagnoses the missing modifier. `TypeAliasAndAddressorTests` also uses all five addressor exports identified in SwiftUICore and representative imported type-alias extension members.
