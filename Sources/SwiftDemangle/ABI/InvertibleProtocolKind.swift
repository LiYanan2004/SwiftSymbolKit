//
//  InvertibleProtocolKind.swift
//  SwiftSymbolKit
//
//  Created by Yanan Li on 2026/9/28.
//

/// Invertible protocol kinds defined by the Swift ABI.
/// Source: https://github.com/swiftlang/swift/blob/main/include/swift/ABI/InvertibleProtocols.def
public enum InvertibleProtocolKind: UInt64, Sendable {
    case copyable = 0
    case escapable = 1
    
    public var sourceName: String {
        switch self {
            case .copyable: "Copyable"
            case .escapable: "Escapable"
        }
    }
}
