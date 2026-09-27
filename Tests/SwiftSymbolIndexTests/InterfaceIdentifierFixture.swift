/// Identifier spellings validated by the Swift parser during interface export.
enum InterfaceIdentifierFixture: CaseIterable {
    case ordinary, reserved, literalKeyword, contextual, unicode, emoji, invalid

    var input: String {
        switch self {
        case .ordinary: return "value"
        case .reserved: return "class"
        case .literalKeyword: return "true"
        case .contextual: return "async"
        case .unicode: return "名称"
        case .emoji: return "🦉"
        case .invalid: return "value\nimport Other"
        }
    }

    var expected: String? {
        switch self {
        case .ordinary: return "value"
        case .reserved: return "`class`"
        case .literalKeyword: return "`true`"
        case .contextual: return "async"
        case .unicode: return "名称"
        case .emoji: return "🦉"
        case .invalid: return nil
        }
    }
}
