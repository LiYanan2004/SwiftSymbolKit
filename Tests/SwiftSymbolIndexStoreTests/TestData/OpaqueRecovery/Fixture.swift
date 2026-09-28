public protocol P {}
public protocol Q {}
public struct Payload: P, Q {}
public class Base { public init() {} }
public func simple() -> some P { Payload() }
public func composition() -> some P & Q { Payload() }
public func external() -> some Equatable { 42 }
public func superclass() -> some Base { Base() }
public func multiple() -> (some P, some Q) { (Payload(), Payload()) }
public func sequence<Element>(_ element: Element) -> some Sequence<Element> { [element] }
public struct Outer<Value: P> {
    public func member() -> some Q { Payload() }
    public func generic<Other: Q>(_ value: Other) -> some P { Payload() }
    public struct Inner {
        public func nested() -> some Q { Payload() }
    }
}
