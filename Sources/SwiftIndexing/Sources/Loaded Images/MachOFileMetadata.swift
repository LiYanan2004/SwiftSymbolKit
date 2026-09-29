import Foundation
import MachOKit

/// Gives file-relative metadata and cache dependencies distinct address spaces.
/// No file is loaded for execution; MachOKit resolves encoded pointer fixups.
final class MachOFileMetadata {
    private static let fileAddressBase: UInt64 = 1 << 60
    let file: MachOFile
    private let data: Data
    private let preferredAddress: UInt64
    private lazy var cache = DyldCacheLoaded.current
    private lazy var cacheImages = cache.map { Array($0.machOImages()) } ?? []
    private lazy var cacheSymbols = MachOImageSymbolResolver(images: cacheImages)
    private lazy var symbols = MachOSymbolIndex(machO: file)
    
    init(file: MachOFile) throws {
        guard !file.isLoadedFromDyldCache, let preferredAddress = file.preferredLoadAddress else {
            throw ReadError.unsupportedFile
        }
        self.file = file
        self.preferredAddress = preferredAddress
        data = try Data(contentsOf: file.url, options: .mappedIfSafe)
    }
    
    func symbol(_ name: String) throws -> UInt64 {
        let normalized = MangledSymbolSource.normalizedSymbol(name)
        if let offset = symbols.offsets[normalized] {
            return try address(for: UInt64(offset))
        }
        if let symbol = symbols.exports[normalized],
           symbol.flags.kind == .regular, !symbol.flags.contains(.reexport),
           symbol.resolverOffset == nil, let offset = symbol.offset, offset >= 0 {
            return try adding(Int64(offset), to: Self.fileAddressBase)
        }
        throw LoadedImageSource.ReadError.missingExportedDescriptor(name)
    }
    
    func bytes(at address: UInt64, count: Int) throws -> [UInt8] {
        guard count >= 0, count <= 1 << 20, address <= UInt64.max - UInt64(count) else {
            throw OpaqueTypeDescriptorReader.ReadError.metadataReadOutOfBounds
        }
        if count == 0 { return [] }
        if address < Self.fileAddressBase {
            try validateCacheAddress(address, count: count)
            return try OpaqueTypeDescriptorReader.memoryBytes(at: address, count: count)
        }
        let virtualAddress = try virtualAddress(for: address)
        guard file.segments64.contains(where: {
            virtualAddress >= $0.vmaddr && virtualAddress - $0.vmaddr <= $0.filesize &&
            UInt64(count) <= $0.filesize - (virtualAddress - $0.vmaddr)
        }), let offset = file.fileOffset(of: virtualAddress) else { throw ReadError.unmappedAddress(address) }
        let absoluteOffset = try adding(Int64(file.headerStartOffset), to: offset)
        guard absoluteOffset <= UInt64(data.count), UInt64(count) <= UInt64(data.count) - absoluteOffset else {
            throw OpaqueTypeDescriptorReader.ReadError.metadataReadOutOfBounds
        }
        return Array(data[Int(absoluteOffset)..<Int(absoluteOffset) + count])
    }
    
    func pointer(at address: UInt64) throws -> UInt64 {
        if address < Self.fileAddressBase {
            let raw = try bytes(at: address, count: 8).withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }
            let target = file.stripPointerTags(of: raw)
            try validateCacheAddress(target, count: 1)
            return target
        }
        let virtualAddress = try virtualAddress(for: address)
        let raw = try bytes(at: address, count: 8).withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }
        guard raw != 0 else { throw OpaqueTypeDescriptorReader.ReadError.nullIndirectReference }
        guard let offset = file.fileOffset(of: virtualAddress) else { throw ReadError.unmappedAddress(address) }
        if let (binding, addend) = file.resolveBind(at: offset),
           let name = file.dyldChainedFixups?.symbolName(for: binding.info.nameOffset) {
            let target = try boundSymbol(name, ordinal: binding.info.libraryOrdinal)
            return try adding(Int64(binding.info.addend), to: adding(Int64(bitPattern: addend), to: target))
        }
        if let offset = file.resolveRebase(at: offset) {
            guard let displacement = Int64(exactly: offset) else { throw ReadError.unmappedAddress(offset) }
            return try adding(displacement, to: Self.fileAddressBase)
        }
        if let binding = (file.bindingSymbols + file.weakBindingSymbols).first(where: { $0.address(in: file) == UInt(virtualAddress) }) {
            return try adding(Int64(binding.addend), to: boundSymbol(binding.symbolName, ordinal: binding.libraryOrdinal))
        }
        // Traditional rebases retain the unslid virtual address in the file.
        return try self.address(for: file.stripPointerTags(of: raw))
    }
    
    private func boundSymbol(_ name: String, ordinal: Int) throws -> UInt64 {
        if ordinal == 0 { return try symbol(name) }
        let identity = try LoadedImageSource.identity(of: file)
        guard identity.target.platform == .macOS, identity.target.environment == .native,
              ordinal > 0, file.dependencies.indices.contains(ordinal - 1) else {
            throw ReadError.unresolvedImport(name)
        }
        let installName = file.dependencies[ordinal - 1].dylib.name
        guard let image = cacheImages.first(where: { $0.path == installName }),
              image.header.cpuType == file.header.cpuType else { throw ReadError.unresolvedImport(name) }
        return try cacheSymbols.address(of: name, in: image)
    }
    
    private func address(for virtualAddress: UInt64) throws -> UInt64 {
        guard virtualAddress >= preferredAddress else { throw ReadError.unmappedAddress(virtualAddress) }
        let offset = virtualAddress - preferredAddress
        guard offset < Self.fileAddressBase else { throw ReadError.unmappedAddress(virtualAddress) }
        return Self.fileAddressBase + offset
    }
    
    private func virtualAddress(for address: UInt64) throws -> UInt64 {
        guard address >= Self.fileAddressBase,
              let displacement = Int64(exactly: address - Self.fileAddressBase) else {
            throw ReadError.unmappedAddress(address)
        }
        return try adding(displacement, to: preferredAddress)
    }
    
    private func validateCacheAddress(_ address: UInt64, count: Int) throws {
        guard let cache, let slide = cache.slide else { throw ReadError.unmappedAddress(address) }
        let start = try adding(Int64(slide), to: cache.header.sharedRegionStart)
        guard address >= start, address - start < cache.header.sharedRegionSize,
              UInt64(count) <= cache.header.sharedRegionSize - (address - start) else {
            throw ReadError.unmappedAddress(address)
        }
    }
    
    private func adding(_ displacement: Int64, to address: UInt64) throws -> UInt64 {
        if displacement < 0 {
            guard displacement != .min, address >= UInt64(-displacement) else {
                throw OpaqueTypeDescriptorReader.ReadError.relativePointerUnderflow
            }
            return address - UInt64(-displacement)
        }
        let (result, overflow) = address.addingReportingOverflow(UInt64(displacement))
        guard !overflow else { throw OpaqueTypeDescriptorReader.ReadError.relativePointerOverflow }
        return result
    }
    
    enum ReadError: Error, CustomStringConvertible {
        case unsupportedFile
        case unmappedAddress(UInt64)
        case unresolvedImport(String)
        
        var description: String {
            switch self {
                case .unsupportedFile:
                    return "Opaque recovery requires a standalone Mach-O file with a preferred load address"
                case let .unmappedAddress(address):
                    return "Unmapped metadata address: 0x\(String(address, radix: 16))"
                case let .unresolvedImport(name):
                    return "Cannot resolve file metadata import from compatible dependencies: \(name)"
            }
        }
    }
}

