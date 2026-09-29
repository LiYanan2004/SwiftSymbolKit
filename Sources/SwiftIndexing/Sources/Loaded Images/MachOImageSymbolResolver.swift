import MachOKit

/// Decode each image's symbol tables once for a metadata recovery operation.
struct MachOSymbolIndex {
    let offsets: [String: Int]
    let exports: [String: ExportedSymbol]

    init(machO: some MachORepresentable) {
        var offsets: [String: Int] = [:]
        for symbol in machO.symbols where symbol.nlist.flags?.type == .sect &&
            symbol.nlist.flags?.stab == nil && symbol.offset >= 0 {
            offsets[MangledSymbolSource.normalizedSymbol(symbol.name)] = symbol.offset
        }
        self.offsets = offsets
        exports = Dictionary(machO.exportedSymbols.map {
            (MangledSymbolSource.normalizedSymbol($0.name), $0)
        }, uniquingKeysWith: { first, _ in first })
    }
}

final class MachOImageSymbolResolver {
    private let images: [String: MachOImage]
    private var indexes: [UInt: MachOSymbolIndex] = [:]

    init(images: [MachOImage]) {
        self.images = Dictionary(images.compactMap { image in
            image.path.map { (path: $0, image: image) }
        }, uniquingKeysWith: { first, _ in first })
    }

    func address(of name: String, in image: MachOImage, depth: Int = 0) throws -> UInt64 {
        guard depth < 64 else { throw LoadedImageSource.ReadError.unsupportedSymbol(name) }
        let identifier = UInt(bitPattern: image.ptr)
        if indexes[identifier] == nil {
            indexes[identifier] = MachOSymbolIndex(machO: image)
        }
        guard let index = indexes[identifier] else {
            throw LoadedImageSource.ReadError.missingExportedDescriptor(name)
        }
        let normalized = MangledSymbolSource.normalizedSymbol(name)
        if let offset = index.offsets[normalized] {
            return try address(offset: offset, in: image)
        }
        guard let symbol = index.exports[normalized] else {
            throw LoadedImageSource.ReadError.missingExportedDescriptor(name)
        }
        if symbol.flags.contains(.reexport), let ordinal = symbol.ordinal, ordinal > 0,
           ordinal <= image.dependencies.count {
            let dependency = image.dependencies[Int(ordinal - 1)].dylib.name
            guard let target = images[dependency] else {
                throw LoadedImageSource.ReadError.imageNotInSharedCache(dependency)
            }
            let importedName = symbol.importedName.flatMap { $0.isEmpty ? nil : $0 } ?? name
            return try address(of: importedName, in: target, depth: depth + 1)
        }
        guard symbol.flags.kind == .regular, symbol.resolverOffset == nil,
              let offset = symbol.offset, offset >= 0 else {
            throw LoadedImageSource.ReadError.unsupportedSymbol(name)
        }
        return try address(offset: offset, in: image)
    }

    private func address(offset: Int, in image: MachOImage) throws -> UInt64 {
        let (address, overflow) = UInt64(UInt(bitPattern: image.ptr)).addingReportingOverflow(UInt64(offset))
        guard !overflow else { throw OpaqueTypeDescriptorReader.ReadError.relativePointerOverflow }
        return address
    }
}
