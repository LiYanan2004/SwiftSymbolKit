enum ConstrainedExistentialInterfaceFixture: CaseIterable {
    case sequence, asyncIterator, boxTag, font, color, gradient, animation

    var input: String {
        switch self {
        case .sequence: return "_$s7SwiftUI28BreadthFirstSearchEvaluationO8continueyACyxq_GST_px7ElementRts_XPcAEmr0_lFWC"
        case .asyncIterator: return "_$s10AppIntents26_AsyncIntentItemCollectionVyACyxq_GScI_px7ElementRts_q_7FailureRtsXPAA01_cdE15IteratorOptionsVccfC"
        case .boxTag: return "_$s7SwiftUI13CodableBoxTagP3boxAA0cD0_p0D0QzAGRS_XPXpvgTj"
        case .font: return "_$s7SwiftUI4FontVAAE11ProviderTagO3boxAA10CodableBox_pAA03AnycH0C0H0AA0igH0PRts_XPXpvg"
        case .color: return "_$s7SwiftUI5ColorVAAE11ProviderTagO3boxAA10CodableBox_pAA03AnycH0C0H0AA0igH0PRts_XPXpvg"
        case .gradient: return "_$s7SwiftUI8GradientVAAE11ProviderTagO3boxAA10CodableBox_pAA03AnycH0C0H0AA0igH0PRts_XPXpvg"
        case .animation: return "_$s7SwiftUI16AnimationContextVAAE19finishingDefinitionAA0c9FinishingF0_px5ValueRts_XPXpSgvM"
        }
    }

    var expected: String {
        switch self {
        case .sequence: return "case `continue`(_: any Swift.Sequence<A>)"
        case .asyncIterator: return "-> any Swift.AsyncIteratorProtocol<A, B>"
        case .boxTag: return "var box: any SwiftUI.CodableBox<Self.Box>.Type { get }"
        case .font: return "public var box: any SwiftUI.CodableBox<SwiftUI.AnyFontBox>.Type { get }"
        case .color: return "public var box: any SwiftUI.CodableBox<SwiftUI.AnyColorBox>.Type { get }"
        case .gradient: return "public var box: any SwiftUI.CodableBox<SwiftUI.AnyGradientBox>.Type { get }"
        case .animation: return "public var finishingDefinition: Swift.Optional<any SwiftUI.AnimationFinishingDefinition<A>.Type> { get set }"
        }
    }

    var contextSymbols: [String] {
        switch self {
        case .animation: return ["_$s7SwiftUI16AnimationContextV11environment19isLogicallyCompleteACyxG14AttributeGraph04WeakI0VyAA17EnvironmentValuesVGSg_SbtcfC"]
        default: return []
        }
    }
}
