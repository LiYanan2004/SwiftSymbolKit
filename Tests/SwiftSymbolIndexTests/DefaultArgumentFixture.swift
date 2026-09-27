enum DefaultArgumentFixture: CaseIterable {
    case initializer, extensionMethod, staticMethod

    var input: String {
        switch self {
        case .initializer:
            return "_$s9WidgetKit0A22ContainerShapeModifierV12cornerRadiusAC12CoreGraphics7CGFloatVSg_tcfcfA_"
        case .extensionMethod:
            return "_$s7SwiftUI4ViewP9WidgetKitE22applyCommonEnvironment6widget7metrics14overrideFamilyQrSo9CHSWidgetC_So0M7MetricsCSo0mL0VSgtFfA1_"
        case .staticMethod:
            return "_$s9WidgetKit13ControlActionV06legacyD0yACxm10AppIntents0F6IntentRzlFZfA_"
        }
    }
}
