//
//  SymbolEvidenceSource.swift
//  SwiftSymbolKit
//
//  Created by Yanan Li on 2026/9/28.
//

public struct SymbolEvidenceSource: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case mangledSymbols
        case swiftInterface
        case dyldSharedCache
        case compilerDump
    }

    public let kind: Kind
    public let location: String
    /// Content digest, image UUID, or another reproducible artifact identity.
    public let artifactIdentifier: String
    /// Shared by artifacts derived from the same input; used to avoid double counting.
    public let lineageIdentifier: String
    /// Includes the tool version and invocation when the artifact was generated.
    public let producer: String?

    public init(kind: Kind, location: String, artifactIdentifier: String,
                lineageIdentifier: String, producer: String? = nil) {
        self.kind = kind
        self.location = location
        self.artifactIdentifier = artifactIdentifier
        self.lineageIdentifier = lineageIdentifier
        self.producer = producer
    }
}
