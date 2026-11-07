import CryptoKit
import Foundation
import SwiftParser
import SwiftSyntax

// Structural project metrics, not a claim of SonarQube equivalence. See docs/QUALITY.md.
struct FunctionMetric: Codable {
    let file: String
    let identity: String
    let start: Int
    let end: Int
    let cyclomatic: Int
    let cognitive: Int
    let bodyHash: String
}

final class Complexity: SyntaxVisitor {
    var cyclomatic = 1
    var cognitive = 0
    private var nesting = 0

    init() { super.init(viewMode: .sourceAccurate) }

    private func branch() -> SyntaxVisitorContinueKind {
        cyclomatic += 1
        cognitive += 1 + nesting
        nesting += 1
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        nesting += 1
        return .visitChildren
    }
    override func visitPost(_ node: ClosureExprSyntax) { nesting -= 1 }
    override func visit(_ node: IfExprSyntax) -> SyntaxVisitorContinueKind {
        if node.parent?.is(IfExprSyntax.self) == true {
            cyclomatic += 1
            cognitive += 1
            return .visitChildren
        }
        return branch()
    }
    override func visitPost(_ node: IfExprSyntax) { if node.parent?.is(IfExprSyntax.self) != true { nesting -= 1 } }
    override func visit(_ node: GuardStmtSyntax) -> SyntaxVisitorContinueKind {
        cyclomatic += 1
        cognitive += 1
        return .visitChildren
    }
    override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind { branch() }
    override func visitPost(_ node: ForStmtSyntax) { nesting -= 1 }
    override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind { branch() }
    override func visitPost(_ node: WhileStmtSyntax) { nesting -= 1 }
    override func visit(_ node: RepeatStmtSyntax) -> SyntaxVisitorContinueKind { branch() }
    override func visitPost(_ node: RepeatStmtSyntax) { nesting -= 1 }
    override func visit(_ node: CatchClauseSyntax) -> SyntaxVisitorContinueKind { branch() }
    override func visitPost(_ node: CatchClauseSyntax) { nesting -= 1 }
    override func visit(_ node: TernaryExprSyntax) -> SyntaxVisitorContinueKind { branch() }
    override func visitPost(_ node: TernaryExprSyntax) { nesting -= 1 }
    override func visit(_ node: SwitchExprSyntax) -> SyntaxVisitorContinueKind {
        cognitive += 1 + nesting
        nesting += 1
        return .visitChildren
    }
    override func visitPost(_ node: SwitchExprSyntax) { nesting -= 1 }
    override func visit(_ node: SwitchCaseSyntax) -> SyntaxVisitorContinueKind {
        cyclomatic += 1
        return .visitChildren
    }
    override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        let operators = node.elements.compactMap { $0.as(BinaryOperatorExprSyntax.self)?.operator.text }.filter {
            $0 == "&&" || $0 == "||"
        }
        cyclomatic += operators.count
        var previous: String?
        for op in operators {
            if op != previous { cognitive += 1 }
            previous = op
        }
        return .visitChildren
    }
    override func visit(_ token: TokenSyntax) -> SyntaxVisitorContinueKind {
        if token.tokenKind == .keyword(.else), let parent = token.parent?.as(IfExprSyntax.self),
            parent.elseBody?.is(IfExprSyntax.self) != true
        {
            cognitive += 1
        }
        return .visitChildren
    }
}

final class Functions: SyntaxVisitor {
    let file: String
    let converter: SourceLocationConverter
    var metrics: [FunctionMetric] = []

    init(file: String, tree: SourceFileSyntax) {
        self.file = file
        converter = SourceLocationConverter(fileName: file, tree: tree)
        super.init(viewMode: .sourceAccurate)
    }

    private func scope(_ node: some SyntaxProtocol) -> String {
        var result: [String] = []
        var parent = node.parent
        while let current = parent {
            if let type = current.as(StructDeclSyntax.self) { result.append(type.name.text) }
            if let type = current.as(ClassDeclSyntax.self) { result.append(type.name.text) }
            if let type = current.as(EnumDeclSyntax.self) { result.append(type.name.text) }
            if let type = current.as(ActorDeclSyntax.self) { result.append(type.name.text) }
            if let type = current.as(ExtensionDeclSyntax.self) { result.append(type.extendedType.trimmedDescription) }
            parent = current.parent
        }
        return result.reversed().joined(separator: ".")
    }

    private func record(_ node: some SyntaxProtocol, name: String, body: some SyntaxProtocol) {
        let complexity = Complexity()
        complexity.walk(body)
        let tokens = body.tokens(viewMode: .sourceAccurate).filter { $0.tokenKind != .semicolon }.map(\.text)
        let data = try! JSONEncoder().encode(tokens)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        metrics.append(
            FunctionMetric(
                file: file, identity: scope(node) + "." + name,
                start: converter.location(for: body.positionAfterSkippingLeadingTrivia).line,
                end: converter.location(for: body.endPositionBeforeTrailingTrivia).line,
                cyclomatic: complexity.cyclomatic, cognitive: complexity.cognitive, bodyHash: digest))
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if let body = node.body {
            let parameters = node.signature.parameterClause.parameters.map {
                $0.firstName.text + ":" + $0.type.trimmedDescription
            }.joined(separator: ",")
            record(node, name: node.name.text + "(" + parameters + ")", body: body)
        }
        return .visitChildren
    }
    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        if let body = node.body {
            let parameters = node.signature.parameterClause.parameters.map {
                $0.firstName.text + ":" + $0.type.trimmedDescription
            }.joined(separator: ",")
            record(node, name: "init(" + parameters + ")", body: body)
        }
        return .visitChildren
    }
    override func visit(_ node: PatternBindingSyntax) -> SyntaxVisitorContinueKind {
        if let body = node.accessorBlock {
            record(node, name: "property:" + node.pattern.trimmedDescription, body: body)
        }
        return .visitChildren
    }
}

func analyze(_ path: String) throws -> [FunctionMetric] {
    let source = try String(contentsOfFile: path, encoding: .utf8)
    let tree = Parser.parse(source: source)
    guard !tree.hasError else { throw NSError(domain: "Unparsable Swift: " + path, code: 1) }
    let visitor = Functions(file: path, tree: tree)
    visitor.walk(tree)
    return visitor.metrics
}

@main struct MetricsCommand {
    static func main() {
        do {
            let metrics = try CommandLine.arguments.dropFirst().flatMap(analyze)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            print(String(decoding: try encoder.encode(metrics), as: UTF8.self))
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }
}
