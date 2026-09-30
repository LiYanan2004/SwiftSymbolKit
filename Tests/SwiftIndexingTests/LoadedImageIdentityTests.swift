import MachO
import MachOKit
import Testing
@testable import SwiftIndexing

struct LoadedImageIdentityTests {
    @Test(arguments: [UInt32(12), 0x8000_000c, 0x8200_000c])
    func recognizesArm64eX1WithPointerAuthenticationCapabilities(subtype: UInt32) throws {
        try MachOImageFixture(cpuSubtype: cpu_subtype_t(bitPattern: subtype)).withImage { machO in
            let identity = try LoadedImageSource.identity(of: machO)
            #expect(identity.target == (try CompilerTarget(parsing: "arm64e.x1-macos")))
            #expect(identity.identifier == "00112233445566778899aabbccddeeff")
        }
    }

    @Test func preservesExistingArchitectures() throws {
        let fixtures: [(cpu_type_t, cpu_subtype_t, CompilerTarget.Architecture)] = [
            (CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64_ALL, .arm64),
            (CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64_V8, .arm64),
            (CPU_TYPE_ARM64, CPU_SUBTYPE_ARM64E, .arm64e),
            (CPU_TYPE_ARM64, cpu_subtype_t(bitPattern: 0x8000_0002), .arm64e),
            (CPU_TYPE_ARM64, 3, .arm64_x1),
            (CPU_TYPE_X86_64, CPU_SUBTYPE_X86_64_ALL, .x86_64),
            (CPU_TYPE_X86_64, CPU_SUBTYPE_X86_64_H, .x86_64h),
        ]
        for (cpuType, cpuSubtype, expected) in fixtures {
            try MachOImageFixture(cpuType: cpuType, cpuSubtype: cpuSubtype).withImage { machO in
                let identity = try LoadedImageSource.identity(of: machO)
                #expect(identity.target.architecture == expected)
            }
        }
    }

    @Test func rejectsUnsupportedCPUType() {
        MachOImageFixture(cpuType: CPU_TYPE_ARM, cpuSubtype: 12).withImage { machO in
            #expect(throws: LoadedImageSource.ReadError.self) { try LoadedImageSource.identity(of: machO) }
        }
    }

    @Test(arguments: [CPU_TYPE_ARM64, CPU_TYPE_X86_64])
    func rejectsUnknownSubtypes(cpuType: cpu_type_t) {
        MachOImageFixture(cpuType: cpuType, cpuSubtype: 0x7f).withImage { machO in
            #expect(throws: LoadedImageSource.ReadError.self) { try LoadedImageSource.identity(of: machO) }
        }
    }

    @Test func acceptsLegacyMacOSVersionCommand() throws {
        try MachOImageFixture(usesLegacyVersionCommand: true).withImage { machO in
            let identity = try LoadedImageSource.identity(of: machO)
            #expect(identity.target.platform == .macOS)
        }
    }

    @Test func recognizesFilePlatforms() throws {
        for (platform, target) in [(PLATFORM_IOS, "arm64-ios"),
                                   (PLATFORM_IOSSIMULATOR, "arm64-ios-simulator"),
                                   (PLATFORM_MACCATALYST, "arm64-ios-macabi")] {
            try MachOImageFixture(platform: UInt32(platform)).withImage { image in
                let identity = try LoadedImageSource.identity(of: image)
                #expect(identity.target == (try CompilerTarget(parsing: target)))
            }
        }
    }

    @Test func rejectsUnsupportedImageMetadata() {
        let fixtures = [
            MachOImageFixture(magic: MH_MAGIC),
            MachOImageFixture(magic: MH_CIGAM_64),
            MachOImageFixture(platform: nil),
            MachOImageFixture(includesUUID: false),
        ]
        for fixture in fixtures {
            fixture.withImage { machO in
                #expect(throws: LoadedImageSource.ReadError.self) { try LoadedImageSource.identity(of: machO) }
            }
        }
    }
}

/// MachOKit views borrow this buffer only for the duration of the test closure.
struct MachOImageFixture {
    var cpuType: cpu_type_t = CPU_TYPE_ARM64
    var cpuSubtype: cpu_subtype_t = CPU_SUBTYPE_ARM64_ALL
    var magic: UInt32 = MH_MAGIC_64
    var platform: UInt32? = UInt32(PLATFORM_MACOS)
    var usesLegacyVersionCommand = false
    var includesUUID = true

    func withImage(_ body: (MachOImage) throws -> Void) rethrows {
        var header = mach_header_64()
        header.magic = magic
        header.cputype = cpuType
        header.cpusubtype = cpuSubtype
        var commands: [UInt8] = []
        if includesUUID {
            var command = uuid_command()
            command.cmd = UInt32(LC_UUID)
            command.cmdsize = UInt32(MemoryLayout<uuid_command>.size)
            command.uuid = (0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
                            0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff)
            commands += withUnsafeBytes(of: command, Array.init)
            header.ncmds += 1
        }
        if usesLegacyVersionCommand {
            var command = version_min_command()
            command.cmd = UInt32(LC_VERSION_MIN_MACOSX)
            command.cmdsize = UInt32(MemoryLayout<version_min_command>.size)
            commands += withUnsafeBytes(of: command, Array.init)
            header.ncmds += 1
        } else if let platform {
            var command = build_version_command()
            command.cmd = UInt32(LC_BUILD_VERSION)
            command.cmdsize = UInt32(MemoryLayout<build_version_command>.size)
            command.platform = platform
            commands += withUnsafeBytes(of: command, Array.init)
            header.ncmds += 1
        }
        header.sizeofcmds = UInt32(commands.count)
        let bytes = withUnsafeBytes(of: header, Array.init) + commands
        try bytes.withUnsafeBytes { buffer in
            try body(MachOImage(ptr: buffer.baseAddress!.assumingMemoryBound(to: mach_header.self)))
        }
    }
}
