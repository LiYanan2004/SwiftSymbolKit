public struct Buffer<Element> {
    private let pointer: UnsafeMutablePointer<Element>
    public init(_ pointer: UnsafeMutablePointer<Element>) { self.pointer = pointer }
    public subscript(_ index: Int) -> Element {
        unsafeAddress { UnsafePointer(pointer + index) }
        nonmutating unsafeMutableAddress { pointer + index }
    }
}
