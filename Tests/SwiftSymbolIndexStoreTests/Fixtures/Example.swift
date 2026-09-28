public protocol SampleProtocol { associatedtype Element; func hello() }
public struct Foo<T> {
    public struct Boo { public func hello() {} }
    public var value: T
    public var computed: Int { get { 0 } set {} }
    public static func hello(_ input: Int) -> String { "" }
    public func hello(value: String) async throws -> Int { 0 }
    public func transform<U>(_ body: (T) -> U) -> U { body(value) }
    public init(value: T) { self.value = value }
}
public enum Choice { case empty; case value(Int) }
public class Object { public init() {} ; deinit {} }
extension Foo: SampleProtocol where T: Equatable {
    public typealias Element = T
    public func hello() {}
}
extension Array where Element: SampleProtocol { public func inspect() {} }
public func identity<each T>(_ value: repeat each T) -> (repeat each T) { (repeat each value) }
public func choose(_ value: Int) {}
public func choose(_ value: String) {}
public func labels(_ first: Int, second: Int) {}
public enum Failure: Error { case failed }
public func checked() throws(Failure) {}
public func transfer(_ value: sending String) -> sending String { value }
extension Foo {
    public subscript(index: Int) -> T { value }
    public static var count: Int { 0 }
}
public func opaque() -> some Equatable { 0 }
