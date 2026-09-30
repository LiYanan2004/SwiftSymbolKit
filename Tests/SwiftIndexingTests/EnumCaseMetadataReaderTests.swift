import MachOKit
import SwiftDemangle
import Testing
@testable import SwiftIndexing

struct EnumCaseMetadataReaderTests {
    @Test func readsEffectiveIndirection() throws {
        let bytes = fixture()
        try bytes.withUnsafeBytes { buffer in
            let base = UInt64(UInt(bitPattern: buffer.baseAddress!))
            let enumeration = try #require(SwiftSymbol("$s1M1EOMn").children.first?.children.first?.children.first)
            let reader = EnumCaseMetadataReader(metadata: .init(machO: MachOImage.current()))
            let records = try reader.read(at: base + 16, enumeration: enumeration)
            #expect(records.map(\.name) == ["empty", "boxed"])
            #expect(records.map(\.isIndirect) == [false, true])
        }
    }

    @Test(arguments: ["missingFields", "recordSize", "recordCount", "recordFlags", "duplicateNames", "wrongOwner"])
    func rejectsMissingAndMalformedReflection(failure: String) throws {
        var bytes = fixture()
        switch failure {
        case "missingFields": bytes.replaceSubrange(32..<36, with: [0, 0, 0, 0])
        case "recordSize": bytes[58] = 8
        case "recordCount": bytes[62] = 2
        case "recordFlags": bytes[76] = 2
        case "duplicateNames": bytes[84] = 12 // The second name points to "empty".
        case "wrongOwner": bytes[40] = 70 // F instead of E.
        default: break
        }
        try bytes.withUnsafeBytes { buffer in
            let base = UInt64(UInt(bitPattern: buffer.baseAddress!))
            let enumeration = try #require(SwiftSymbol("$s1M1EOMn").children.first?.children.first?.children.first)
            let reader = EnumCaseMetadataReader(metadata: .init(machO: MachOImage.current()))
            #expect(throws: (any Error).self) { try reader.read(at: base + 16, enumeration: enumeration) }
        }
    }

    private func fixture() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 112)
        bytes[8] = 4
        bytes[12] = 77 // Module M.
        bytes[16] = 18 // Enum descriptor.
        withUnsafeBytes(of: Int32(-20)) { bytes.replaceSubrange(20..<24, with: $0) }
        bytes[24] = 16
        bytes[32] = 16
        bytes[40] = 69 // Enum E.
        bytes[56] = 2 // FieldDescriptorKind::Enum.
        bytes[58] = 12
        bytes[60] = 2
        bytes[72] = 24
        bytes[76] = 1 // IsIndirectCase.
        bytes[84] = 18
        bytes.replaceSubrange(96..<102, with: Array("empty\0".utf8))
        bytes.replaceSubrange(102..<108, with: Array("boxed\0".utf8))
        return bytes
    }
}
