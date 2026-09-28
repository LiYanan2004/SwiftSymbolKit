enum TextBasedStubFixture: CaseIterable {
    case multipleArchitectures
    case legacy
    case empty

    var input: String {
        switch self {
        case .multipleArchitectures:
            return """
            --- !tapi-tbd
            tbd-version: 4
            install-name: /System/Library/Frameworks/Example.framework/Example
            targets: [ arm64-macos, x86_64-macos ]
            exports:
              - targets: [ arm64-macos ]
                symbols: [ '_$s7Example3FooV', _ordinary_c_symbol ]
                weak-def-symbols: [ '_$s7Example3BarV' ]
              - targets: [ x86_64-macos ]
                symbols: [ '_$s7Example3FooV', '_$s7Example3BazV' ]
                thread-local-symbols: [ '_$s7Example3BarV' ]
            reexports:
              - targets: [ arm64-macos ]
                symbols: [ '_$s7Example3BazV', '_$s7Example3QuxV' ]
            undefineds:
              - targets: [ arm64-macos ]
                symbols: [ '_$s7Missing3FooV' ]
            ...
            """
        case .legacy:
            return """
            --- !tapi-tbd-v3
            archs: [ arm64, x86_64 ]
            platform: macosx
            install-name: /usr/lib/libExample.dylib
            exports:
              - archs: [ arm64, x86_64 ]
                symbols: [ '__T0Example', '_$SExample', '_$eExample', _c_symbol ]
            ...
            """
        case .empty:
            return """
            --- !tapi-tbd
            tbd-version: 4
            install-name: /usr/lib/libExample.dylib
            targets: [ arm64-macos ]
            ...
            """
        }
    }

    var expectedSymbols: [String] {
        switch self {
        case .multipleArchitectures:
            return ["_$s7Example3BarV", "_$s7Example3BazV", "_$s7Example3FooV", "_$s7Example3QuxV"]
        case .legacy:
            return ["_$SExample", "_$eExample", "__T0Example"]
        case .empty:
            return []
        }
    }
}
