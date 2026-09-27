public struct PackBox<each Element> {
    public let values: (repeat each Element)
    public init(_ values: repeat each Element) { self.values = (repeat each values) }
}
public func empty(_ value: PackBox<>) {}
public func concrete(_ value: PackBox<Int, String>) {}
public func generic<each Element>(_ value: PackBox<repeat each Element>) {}
public struct Mixed<Head, each Tail> {
    public init(_ head: Head, _ tail: repeat each Tail) {}
}
public func mixed<each Element>(_ value: Mixed<Int, String, repeat each Element>) {}
extension PackBox: Sendable where repeat each Element: Sendable {}
public protocol Marker {}
extension PackBox: Marker where repeat each Element: Equatable {}
