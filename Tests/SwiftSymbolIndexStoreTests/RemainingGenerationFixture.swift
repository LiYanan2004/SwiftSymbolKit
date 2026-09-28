enum RemainingGenerationFixture: CaseIterable {
    case retroactiveConformance, sceneConformance, nestedEnum, optionalConformance, constantParameter

    var input: String {
        switch self {
        case .retroactiveConformance: return "_$s7SwiftUI17_ScrollableLayoutP18decelerationTarget13contentOffset015originalContentH08velocity4sizeSo7CGPointVSgAJ_AjA9_VelocityVySo6CGSizeVAOSQ12CoreGraphicsyHCg_GAOtFTj"
        case .sceneConformance: return "_$s7SwiftUI30_EnvironmentKeyWritingModifierVyxGAA06_SceneF0AAMc"
        case .nestedEnum: return "_$s9SwiftData6SchemaC5IndexC5TypesO5rtreeyAGy_x_qd__GSays14PartialKeyPathCyqd__GGcAImAA15PersistentModelRzAaNRd__r__lFWC"
        case .optionalConformance: return "_$sxSg9SwiftData22RelationshipCollectionABSTRzAB15PersistentModel7ElementRpzlMc"
        case .constantParameter: return "_$s10AppIntents0A8ShortcutV6intent7phrases10shortTitle15systemImageNameACx_SayAA0aC6PhraseVyxGG10Foundation23LocalizedStringResourceVSSYttcAA0A6IntentRzlufC"
        }
    }

    var expected: [String] {
        switch self {
        case .retroactiveConformance: return ["velocity: SwiftUI._Velocity<__C.CGSize>"]
        case .sceneConformance: return ["extension SwiftUI._EnvironmentKeyWritingModifier: SwiftUI._SceneModifier"]
        case .nestedEnum: return ["class Index<A> where A: SwiftData.PersistentModel", "enum Types<A1> where A1: SwiftData.PersistentModel", "case rtree(_: Swift.Array<Swift.PartialKeyPath<A1>>)"]
        case .optionalConformance: return ["extension Swift.Optional: SwiftData.RelationshipCollection", "A.Element: SwiftData.PersistentModel", "A: Swift.Sequence"]
        case .constantParameter: return ["systemImageName: _const Swift.String"]
        }
    }
}
