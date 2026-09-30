import ArgumentParser
import Foundation
import SwiftIndexing

/// Resolves compiler inputs independently of the TBD artifact's location.
enum DeclarationModifierConfigurationResolver {
    static func resolve(
        targetTriple: String,
        sdkPath: String?,
        importSearchPaths: [String] = [],
        frameworkSearchPaths: [String] = []
    ) throws -> DeclarationModifierSource.Configuration {
        let target = try CompilerTarget(parsing: targetTriple)
        let resolvedSDKPath = try sdkPath.map(\.expandingTildeInPath) ?? activeSDKPath(for: target)
        let sdkDirectory = URL(fileURLWithPath: resolvedSDKPath)
        let frameworkDirectory: URL
        if target.environment == .macCatalyst {
            frameworkDirectory = sdkDirectory.appendingPathComponent("System/iOSSupport/System/Library/Frameworks")
        } else if target.platform == .driverKit {
            frameworkDirectory = sdkDirectory.appendingPathComponent("System/DriverKit/System/Library/Frameworks")
        } else {
            frameworkDirectory = sdkDirectory.appendingPathComponent("System/Library/Frameworks")
        }
        return .init(
            sdkPath: resolvedSDKPath,
            targetTriple: targetTriple,
            importSearchPaths: importSearchPaths.map(\.expandingTildeInPath),
            frameworkSearchPaths: frameworkSearchPaths.isEmpty
            ? [frameworkDirectory.path] : frameworkSearchPaths.map(\.expandingTildeInPath)
        )
    }
    
    static func sdkName(for target: CompilerTarget) -> String {
        if target.environment == .macCatalyst { return "macosx" }
        let isSimulator = target.environment == .simulator
        switch target.platform {
            case .macOS: return "macosx"
            case .iOS: return isSimulator ? "iphonesimulator" : "iphoneos"
            case .tvOS: return isSimulator ? "appletvsimulator" : "appletvos"
            case .watchOS: return isSimulator ? "watchsimulator" : "watchos"
            case .visionOS: return isSimulator ? "xrsimulator" : "xros"
            case .bridgeOS: return "bridgeos"
            case .driverKit: return "driverkit"
        }
    }
    
    private static func activeSDKPath(for target: CompilerTarget) throws -> String {
        try Task.checkCancellation()
        let sdkName = sdkName(for: target)
        let process = Process()
        let output = Pipe()
        let diagnosticOutput = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["--sdk", sdkName, "--show-sdk-path"]
        process.standardOutput = output
        process.standardError = diagnosticOutput
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let diagnosticData = diagnosticOutput.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        try Task.checkCancellation()
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0, !path.isEmpty else {
            let diagnostics = String(decoding: diagnosticData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw ValidationError("Failed to resolve the active Xcode's \(sdkName) SDK: \(diagnostics)")
        }
        return path
    }
}
