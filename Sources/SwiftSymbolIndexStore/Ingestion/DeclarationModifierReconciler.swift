import SwiftIndexing

/// Resolves each modifier separately and checks effective enum case storage.
struct DeclarationModifierReconciler {
    let declarations: [SymbolDeclaration.ID: SymbolDeclaration]
    let evidenceByDeclarationID: [SymbolDeclaration.ID: [SymbolEvidence]]

    struct Result {
        var factsBySubject: [SymbolResolvedSubject: [SymbolSupplementalFact.Resolved]] = [:]
        var diagnostics: [SymbolDiagnostic] = []
    }

    func reconcile() -> Result {
        var result = Result()
        for (identifier, observations) in evidenceByDeclarationID {
            let subject = SymbolResolvedSubject.declaration(identifier)
            for (name, related) in Dictionary(grouping: observations, by: { field($0.fact) }) {
                guard let first = related.first else { continue }
                guard related.allSatisfy({ $0.fact == first.fact }) else {
                    result.diagnostics.append(.init(kind: .conflictingInformation,
                        message: "Conflicting \(name) observations; the modifier remains unresolved.",
                        mangledSymbols: declarations[identifier]?.mangledSymbols ?? [], declarationID: identifier))
                    continue
                }
                result.factsBySubject[subject, default: []].append(.init(subject: subject, fact: first.fact,
                    confidence: confidence(related), evidence: related))
            }
        }

        // Decide enum-level suppression before editing any resolved modifiers.
        // This keeps conflict handling independent of dictionary iteration order.
        let indirectEnums = Set(declarations.values.filter {
            $0.kind == .enumeration && result.factsBySubject[.declaration($0.id)]?.contains {
                $0.fact == .modifier(name: "indirect", isPresent: true)
            } == true
        }.map(\.id))
        var suppressedModifiers = Set<SymbolDeclaration.ID>()
        for (identifier, observations) in evidenceByDeclarationID {
            guard let declaration = declarations[identifier], declaration.kind == .enumCase,
                  case .declaration(let owner) = declaration.context else { continue }
            let storage = observations.filter { if case .enumCaseIndirectStorage = $0.fact { return true }; return false }
            guard let first = storage.first else { continue }
            if !storage.allSatisfy({ $0.fact == first.fact }) {
                suppressedModifiers.insert(indirectEnums.contains(owner) ? owner : identifier)
                continue
            }
            guard case .enumCaseIndirectStorage(true) = first.fact, !indirectEnums.contains(owner) else { continue }
            let subject = SymbolResolvedSubject.declaration(identifier)
            var facts = result.factsBySubject[subject] ?? []
            if let position = facts.firstIndex(where: { $0.fact == .modifier(name: "indirect", isPresent: true) }) {
                let related = facts[position].evidence + storage
                facts[position] = .init(subject: subject, fact: facts[position].fact,
                    confidence: confidence(related), evidence: related)
            } else if !observations.contains(where: { if case .modifier("indirect", _) = $0.fact { return true }; return false }) {
                // Binary-only input can express effective indirection as case syntax.
                facts.append(.init(subject: subject, fact: .modifier(name: "indirect", isPresent: true),
                    confidence: confidence(storage), evidence: storage))
            }
            result.factsBySubject[subject] = facts
        }
        for identifier in suppressedModifiers {
            result.factsBySubject[.declaration(identifier), default: []].removeAll {
                if case .modifier("indirect", _) = $0.fact { return true }; return false
            }
        }
        return result
    }

    private func field(_ fact: SymbolSupplementalFact) -> String {
        if case .modifier(let name, _) = fact { return name }
        return "indirect storage"
    }

    private func confidence(_ evidence: [SymbolEvidence]) -> SymbolSupplementalFactConfidence {
        Set(evidence.map { $0.source.lineageIdentifier }).count > 1 ? .corroborated : .singleSource
    }
}
