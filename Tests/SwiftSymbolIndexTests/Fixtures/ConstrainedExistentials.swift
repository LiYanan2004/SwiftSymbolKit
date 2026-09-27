// Compile with -enable-library-evolution -module-name ExistentialFixtures.
public protocol Box<Value> {
    associatedtype Value
}

public func concreteMetatype(_ value: any Box<Int>.Type) {}
public func containerMetatype(_ value: (any Box<Int>).Type) {}
public func sequence(_ value: any Sequence<Int>) {}
public func iterator(_ value: any AsyncIteratorProtocol<Int, Never>) {}
