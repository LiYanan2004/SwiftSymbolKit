import OSLog

enum Loggers {
    private static let subsystem = "com.liyanan2004.SwiftSymbolKit.SwiftSymbolCLI"

    static let symbolExtraction = Logger(subsystem: subsystem, category: "SymbolExtraction")
    static let symbolMerging = Logger(subsystem: subsystem, category: "SymbolMerging")
    static let interfaceGeneration = Logger(subsystem: subsystem, category: "InterfaceGeneration")
}
