import Foundation
import MachO

/// Holds the image open while metadata is copied. dyld resolves shared-cache
/// images and their bindings, including cross-image indirect references.
final class LoadedMachOImage {
    struct ReadError: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    let handle: UnsafeMutableRawPointer

    init(path: String) throws {
        // Public Darwin loader API; loading an image also runs its initializers.
        // https://github.com/apple-oss-distributions/dyld/blob/main/include/dlfcn.h
        guard let handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL | RTLD_FIRST) else {
            throw ReadError(dlerror().map { String(cString: $0) } ?? "Unable to load image: \(path)")
        }
        self.handle = handle
    }

    deinit { dlclose(handle) }

    func symbol(_ mangledName: String) throws -> UInt64 {
        let name = MangledSymbolSource.normalizedSymbol(mangledName)
        guard let pointer = dlsym(handle, name) else { throw ReadError("Missing exported descriptor: \(name)") }
        return UInt64(UInt(bitPattern: pointer))
    }

    /// Copy through Mach rather than dereferencing unchecked metadata pointers.
    /// Invalid or unmapped references produce a recoverable diagnostic.
    // https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/mach/mach_vm.defs
    func bytes(at address: UInt64, count: Int) throws -> [UInt8] {
        guard count >= 0, count <= 1 << 20, address <= UInt64.max - UInt64(count) else {
            throw ReadError("Metadata read exceeds its bounds")
        }
        if count == 0 { return [] }
        var result = [UInt8](repeating: 0, count: count)
        var copied: mach_vm_size_t = 0
        let status = result.withUnsafeMutableBytes { buffer in
            mach_vm_read_overwrite(mach_task_self_, address, UInt64(count),
                UInt64(UInt(bitPattern: buffer.baseAddress!)), &copied)
        }
        guard status == KERN_SUCCESS, copied == count else {
            throw ReadError("Unreadable metadata address: 0x\(String(address, radix: 16))")
        }
        return result
    }

    func value<Value>(at address: UInt64, as type: Value.Type = Value.self) throws -> Value {
        try bytes(at: address, count: MemoryLayout<Value>.size).withUnsafeBytes { $0.loadUnaligned(as: Value.self) }
    }

    func adding(_ displacement: Int64, to address: UInt64) throws -> UInt64 {
        if displacement < 0 {
            guard displacement != .min, address >= UInt64(-displacement) else { throw ReadError("Relative pointer underflow") }
            return address - UInt64(-displacement)
        }
        let (result, overflow) = address.addingReportingOverflow(UInt64(displacement))
        guard !overflow else { throw ReadError("Relative pointer overflow") }
        return result
    }

    func relative(at address: UInt64, indirectable: Bool = false, protocolReference: Bool = false) throws -> UInt64 {
        let displacement: Int32 = try value(at: address)
        guard displacement != 0 else { throw ReadError("Null relative reference") }
        // RelativeTargetProtocolDescriptorPointer uses bit 0 for indirection and
        // bit 1 to distinguish an Objective-C protocol from a Swift descriptor.
        // https://github.com/swiftlang/swift/blob/swift-6.2-RELEASE/include/swift/ABI/MetadataRef.h
        if protocolReference, displacement & 2 != 0 { throw ReadError("Objective-C protocol references are unsupported") }
        let mask: Int32 = protocolReference ? 3 : indirectable ? 1 : 0
        let target = try adding(Int64(displacement & ~mask), to: address)
        return indirectable && displacement & 1 != 0 ? try value(at: target, as: UInt64.self) : target
    }

    func name(at address: UInt64) throws -> String {
        var bytes: [UInt8] = []
        // Defensive parser limit, not an ABI restriction.
        for position in 0..<(1 << 16) {
            let byte: UInt8 = try value(at: adding(Int64(position), to: address))
            if byte == 0 {
                guard let name = String(bytes: bytes, encoding: .utf8) else { throw ReadError("Invalid UTF-8 descriptor name") }
                return name
            }
            bytes.append(byte)
        }
        throw ReadError("Unterminated descriptor name")
    }

    func identity(containing address: UInt64) throws -> (target: IndexingTarget, identifier: String) {
        var information = Dl_info()
        guard let pointer = UnsafeRawPointer(bitPattern: UInt(address)), dladdr(pointer, &information) != 0,
              let headerPointer = information.dli_fbase else { throw ReadError("Descriptor has no owning image") }
        let base = UInt64(UInt(bitPattern: headerPointer))
        let header: mach_header_64 = try value(at: base)
        guard header.magic == MH_MAGIC_64 else { throw ReadError("Only native 64-bit Mach-O images are supported") }
        let architecture: IndexingTarget.Architecture
        switch header.cputype {
        case CPU_TYPE_ARM64:
            architecture = (UInt32(bitPattern: header.cpusubtype) & ~UInt32(CPU_SUBTYPE_MASK)) == UInt32(CPU_SUBTYPE_ARM64E) ? .arm64e : .arm64
        case CPU_TYPE_X86_64:
            architecture = (UInt32(bitPattern: header.cpusubtype) & ~UInt32(CPU_SUBTYPE_MASK)) == UInt32(CPU_SUBTYPE_X86_64_H) ? .x86_64h : .x86_64
        default: throw ReadError("Unsupported image architecture")
        }
        var current = base + UInt64(MemoryLayout<mach_header_64>.size)
        let end = current + UInt64(header.sizeofcmds)
        var identifier: String?
        var platform: UInt32?
        // Command sizes and constants come from the SDK's <mach-o/loader.h>.
        // https://github.com/apple-oss-distributions/xnu/blob/main/EXTERNAL_HEADERS/mach-o/loader.h
        for _ in 0..<header.ncmds {
            guard current + UInt64(MemoryLayout<load_command>.size) <= end else { throw ReadError("Truncated load command") }
            let command: load_command = try value(at: current)
            guard command.cmdsize >= MemoryLayout<load_command>.size, UInt64(command.cmdsize) <= end - current else {
                throw ReadError("Invalid load command size")
            }
            if command.cmd == LC_UUID, command.cmdsize >= MemoryLayout<uuid_command>.size {
                let command: uuid_command = try value(at: current)
                identifier = withUnsafeBytes(of: command.uuid) { $0.map { String(format: "%02x", $0) }.joined() }
            } else if command.cmd == LC_BUILD_VERSION, command.cmdsize >= MemoryLayout<build_version_command>.size {
                let command: build_version_command = try value(at: current)
                platform = command.platform
            } else if command.cmd == LC_VERSION_MIN_MACOSX {
                platform = UInt32(PLATFORM_MACOS)
            }
            current += UInt64(command.cmdsize)
        }
        guard platform == UInt32(PLATFORM_MACOS), let identifier else {
            throw ReadError("Opaque recovery requires a macOS image with an LC_UUID")
        }
        return (.init(architecture: architecture, platform: .macOS), identifier)
    }
}
