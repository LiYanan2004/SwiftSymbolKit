import SwiftParser
import SwiftSyntax

extension InterfaceTypeRenderer {
    /// Validates compiler spellings and maps canonical generic parameters into the emitted scope.
    func compilerType(_ spelling: String) throws -> TypeSyntax {
        let syntax = Parser.parse(source: "typealias __RecoveredType = \(spelling)")
        guard !syntax.hasError, syntax.statements.count == 1,
              let declaration = syntax.statements.first?.item.as(TypeAliasDeclSyntax.self) else {
            throw RenderingError("Invalid compiler type spelling")
        }
        let rewriter = CompilerGenericParameterRewriter(parametersByDepth: genericParametersByDepth)
        guard let type = rewriter.rewrite(declaration.initializer.value).as(TypeSyntax.self), rewriter.unresolvedParameter == nil else {
            throw RenderingError("Unresolved superclass generic parameter: \(rewriter.unresolvedParameter ?? spelling)")
        }
        return type
    }
}

private final class CompilerGenericParameterRewriter: SyntaxRewriter {
    let parametersByDepth: [Int: [String]]
    private(set) var unresolvedParameter: String?

    init(parametersByDepth: [Int: [String]]) {
        self.parametersByDepth = parametersByDepth
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: IdentifierTypeSyntax) -> TypeSyntax {
        let components = node.name.text.split(separator: "_")
        guard components.count == 3, components[0] == "τ", let depth = Int(components[1]), let index = Int(components[2]) else {
            return super.visit(node)
        }
        guard let parameters = parametersByDepth[depth], parameters.indices.contains(index) else {
            unresolvedParameter = node.name.text
            return super.visit(node)
        }
        var rewritten = node
        rewritten.name = .identifier(parameters[index])
        return super.visit(rewritten)
    }
}
