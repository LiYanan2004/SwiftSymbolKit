import ArgumentParser

@main
struct SwiftDemangleCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swift-symbol",
        abstract: "Tools for inspecting Swift symbols and reconstructing declarations.",
        subcommands: [SwiftInterfaceCommand.self]
    )
}
