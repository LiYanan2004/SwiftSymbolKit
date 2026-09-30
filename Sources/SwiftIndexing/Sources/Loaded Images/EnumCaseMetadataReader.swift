import SwiftDemangle

/// Reads effective case indirection from Swift reflection field records.
struct EnumCaseMetadataReader {
    let metadata: OpaqueTypeDescriptorReader

    func read(at descriptor: UInt64, enumeration: DemangledNode) throws -> [(name: String, isIndirect: Bool)] {
        let flags: UInt32 = try metadata.value(at: descriptor)
        guard flags & 0x1f == 18, flags & 0xff00 == 0,
              try metadata.contextType(at: descriptor).children.first?.declarationKey == enumeration.declarationKey else {
            throw ReadError.invalidEnumDescriptor
        }
        // TargetTypeContextDescriptor::Fields is at byte 16. A null pointer
        // means reflection was omitted, so it supplies no negative evidence.
        // https://github.com/swiftlang/swift/blob/swift-6.2-RELEASE/include/swift/ABI/Metadata.h
        let fields = try metadata.relative(at: descriptor + 16)
        let kind: UInt16 = try metadata.value(at: fields + 8)
        let recordSize: UInt16 = try metadata.value(at: fields + 10)
        let count: UInt32 = try metadata.value(at: fields + 12)
        guard (kind == 2 || kind == 3), recordSize == 12, count <= 1 << 16 else {
            throw ReadError.invalidFieldDescriptor
        }
        // FieldRecordFlags::IsIndirectCase = 1. Enum-level indirection applies
        // only to cases with payloads; empty cases always have this bit clear.
        // https://github.com/swiftlang/swift/blob/swift-6.2-RELEASE/include/swift/RemoteInspection/Records.h
        var records: [(name: String, isIndirect: Bool)] = []
        var names = Set<String>()
        for position in 0..<Int(count) {
            let record = try metadata.adding(Int64(16 + position * Int(recordSize)), to: fields)
            let flags: UInt32 = try metadata.value(at: record)
            guard flags & ~1 == 0 else { throw ReadError.invalidFieldRecord }
            let name = try metadata.name(at: metadata.relative(at: record + 8))
            guard !name.isEmpty, names.insert(name).inserted else { throw ReadError.invalidFieldRecord }
            records.append((name, flags & 1 != 0))
        }
        return records
    }

    enum ReadError: Error {
        case invalidEnumDescriptor
        case invalidFieldDescriptor
        case invalidFieldRecord
    }
}
