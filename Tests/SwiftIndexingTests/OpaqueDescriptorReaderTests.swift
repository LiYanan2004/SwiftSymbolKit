import Foundation
import MachOKit
import SwiftDemangle
import Testing
@testable import SwiftIndexing

struct OpaqueDescriptorReaderTests {
    @Test func rejectsInvalidAddressesAndUnsupportedReferences() throws {
        let reader = OpaqueTypeDescriptorReader(machO: MachOImage.current())
        #expect(throws: OpaqueTypeDescriptorReader.ReadError.unreadableMetadataAddress(0)) { try reader.bytes(at: 0, count: 4) }
        #expect(throws: OpaqueTypeDescriptorReader.ReadError.metadataReadOutOfBounds) { try reader.bytes(at: .max, count: 4) }
        #expect(throws: OpaqueTypeDescriptorReader.ReadError.relativePointerUnderflow) { try reader.adding(-1, to: 0) }
        for fixture in UnsupportedReferenceFixture.allCases {
            fixture.input.withUnsafeBytes { buffer in
                let address = UInt64(UInt(bitPattern: buffer.baseAddress!))
                #expect(throws: fixture.expectedError) { try reader.type(at: address) }
            }
        }
    }

    @Test func retainsEmbeddedZeroesAndSignedRelativeOffsets() throws {
        let reader = OpaqueTypeDescriptorReader(machO: MachOImage.current())
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

    @Test(arguments: [UInt64(0), 0xabcd_0000_0000_0000])
    func resolvesIndirectSymbolicReferences(pointerTags: UInt64) throws {
        try MachOImageFixture(cpuSubtype: Int32(bitPattern: 0x8000_000c)).withImage { machO in
            let reader = OpaqueTypeDescriptorReader(machO: machO)
            // Module descriptor at 0, an absolute pointer at 16, and an indirect
            // symbolic reference at 24 whose payload points backwards to 16.
            var bytes = [UInt8](repeating: 0, count: 32)
            bytes[8] = 4
            bytes[12] = 77 // M
            bytes[24] = 2
            withUnsafeBytes(of: Int32(-9)) { bytes.replaceSubrange(25..<29, with: $0) }
            try bytes.withUnsafeMutableBytes { buffer in
                let base = UInt64(UInt(bitPattern: buffer.baseAddress!))
                buffer.storeBytes(of: base | pointerTags, toByteOffset: 16, as: UInt64.self)
                let type = try reader.type(at: base + 24)
                #expect(type.description == "M")
            }
        }
    }

    @Test(arguments: [UInt64(0), 0xabcd_0000_0000_0000])
    func recoversIndirectProtocolConstraints(pointerTags: UInt64) throws {
        try MachOImageFixture(cpuSubtype: Int32(bitPattern: 0x8000_000c)).withImage { machO in
            let reader = OpaqueTypeDescriptorReader(machO: machO)
            var bytes = [UInt8](repeating: 0, count: 80)
            // M at 0; protocol M.P at 16; opaque descriptor at 32, with one
            // parameter and one protocol requirement. The requirement's
            // relative indirect pointer at 60 refers to the pointer slot at 64.
            bytes[8] = 4
            bytes[12] = 77
            bytes[16] = 3
            withUnsafeBytes(of: Int32(-20)) { bytes.replaceSubrange(20..<24, with: $0) }
            bytes[24] = 4
            bytes[28] = 80
            bytes[32] = 0x84
            bytes[40] = 1
            bytes[42] = 1
            bytes[48] = 0x80
            bytes[56] = 20
            bytes[60] = 5
            bytes[76] = 120 // "x": generic parameter at depth 0, index 0.
            let declaration = try SwiftSymbol("$s14OpaqueFixtures6simpleQryF")
            try bytes.withUnsafeMutableBytes { buffer in
                let base = UInt64(UInt(bitPattern: buffer.baseAddress!))
                buffer.storeBytes(of: (base + 16) | pointerTags, toByteOffset: 64, as: UInt64.self)
                let recovered = try reader.read(at: base + 32, declaration: declaration)
                #expect(recovered.count == 1)
                #expect(recovered.first?.constraints.map(\.description) == ["M.P"])
                #expect(recovered.first?.ordinal == 0)
            }
        }
    }
}

private enum UnsupportedReferenceFixture: CaseIterable {
    case accessor, nullIndirect, invalidContext

    var expectedError: OpaqueTypeDescriptorReader.ReadError {
        switch self {
        case .accessor:
            return .unsupportedSymbolicReferenceKind(9)
        case .nullIndirect:
            return .nullIndirectReference
        case .invalidContext:
            return .unsupportedContextDescriptorVersion
        }
    }

    var input: [UInt8] {
        switch self {
        case .accessor:
            return [9, 0, 0, 0, 0, 0]
        case .nullIndirect:
            return [2, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        case .invalidContext:
            return [1, 3, 0, 0, 0, 0xff, 0xff, 0xff, 0xff, 0]
        }
    }
}
