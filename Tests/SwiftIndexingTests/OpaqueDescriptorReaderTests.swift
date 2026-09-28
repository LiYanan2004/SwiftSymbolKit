import Foundation
import Testing
@testable import SwiftIndexing

struct OpaqueDescriptorReaderTests {
    @Test func rejectsInvalidAddressesAndUnsupportedReferences() throws {
        let image = try LoadedMachOImage(path: "/usr/lib/libSystem.B.dylib")
        let reader = OpaqueTypeDescriptorReader(image: image)
        #expect(throws: (any Error).self) { try image.bytes(at: 0, count: 4) }
        #expect(throws: (any Error).self) { try image.bytes(at: .max, count: 4) }
        #expect(throws: (any Error).self) { try image.adding(-1, to: 0) }
        for fixture in UnsupportedReferenceFixture.allCases {
            try fixture.input.withUnsafeBytes { buffer in
                let address = UInt64(UInt(bitPattern: buffer.baseAddress!))
                #expect(throws: (any Error).self) { try reader.type(at: address) }
            }
        }
    }

    @Test func retainsEmbeddedZeroesAndSignedRelativeOffsets() throws {
        let image = try LoadedMachOImage(path: "/usr/lib/libSystem.B.dylib")
        let reader = OpaqueTypeDescriptorReader(image: image)
        // A small standalone ABI fixture places a module descriptor before the
        // symbolic mangling. The reference is negative and includes 0xff bytes.
        var bytes = [UInt8](repeating: 0, count: 32)
        bytes[8] = 4 // Relative Name at offset 8 -> "M" at offset 12.
        bytes[12] = 77
        bytes[16] = 1 // Direct context reference.
        withUnsafeBytes(of: Int32(-17)) { bytes.replaceSubrange(17..<21, with: $0) }
        try bytes.withUnsafeBytes { buffer in
            let base = UInt64(UInt(bitPattern: buffer.baseAddress!))
            let node = try reader.type(at: base + 16)
            #expect(node.kind == .module)
            #expect(node.description == "M")
        }
    }
}

private enum UnsupportedReferenceFixture: CaseIterable {
    case accessor, nullIndirect, invalidContext
    var input: [UInt8] {
        switch self {
        case .accessor: return [9, 0, 0, 0, 0, 0]
        case .nullIndirect: return [2, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        case .invalidContext: return [1, 3, 0, 0, 0, 0xff, 0xff, 0xff, 0xff, 0]
        }
    }
}
