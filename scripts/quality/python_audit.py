"""Python AST identities, Radon CC and pinned complexipy cognitive scores."""

import ast
import hashlib
from pathlib import Path

from complexipy import code_complexity
from radon.complexity import cc_visit

from .common import ROOT, run


class Functions(ast.NodeVisitor):
    def __init__(self):
        self.scope = []
        self.functions = []

    def visit_ClassDef(self, node):
        self.scope.append(node.name)
        self.generic_visit(node)
        self.scope.pop()

    def visit_FunctionDef(self, node):
        self.functions.append((".".join([*self.scope, node.name]), node))
        self.scope.append(node.name)
        self.generic_visit(node)
        self.scope.pop()

    visit_AsyncFunctionDef = visit_FunctionDef


def radon_functions(blocks):
    for block in blocks:
        if hasattr(block, "methods"):
            yield from radon_functions(block.methods)
        else:
            yield block
            yield from radon_functions(block.closures)


def validate_toplevel(tree):
    allowed = (
        ast.Import,
        ast.ImportFrom,
        ast.FunctionDef,
        ast.AsyncFunctionDef,
        ast.ClassDef,
        ast.Assign,
        ast.AnnAssign,
    )
    for node in tree.body:
        if isinstance(node, allowed):
            continue
        if isinstance(node, ast.Expr) and isinstance(node.value, ast.Constant) and isinstance(node.value.value, str):
            continue
        if isinstance(node, ast.If) and ast.unparse(node.test) == "__name__ == '__main__'":
            continue
        raise ValueError("Move executable module-level work into a function, line " + str(node.lineno))


def cognitive_score(node):
    functions = code_complexity(ast.unparse(node)).functions
    if not functions:
        raise ValueError("Missing function metrics at line " + str(node.lineno))
    return functions[0].complexity


def metrics(path):
    source = path.read_text()
    tree = ast.parse(source)
    validate_toplevel(tree)
    visitor = Functions()
    visitor.visit(tree)
    cyclomatic = {item.lineno: item.complexity for item in radon_functions(cc_visit(source))}
    rows = []
    for name, node in visitor.functions:
        if node.lineno not in cyclomatic:
            raise ValueError("Missing function metrics: " + str(path) + ":" + str(node.lineno))
        body = ast.dump(ast.Module(body=node.body, type_ignores=[]), include_attributes=False)
        rows.append(
            dict(
                file=str(path),
                identity=name,
                start=node.lineno,
                end=node.end_lineno,
                cyclomatic=cyclomatic[node.lineno],
                cognitive=cognitive_score(node),
                bodyHash=hashlib.sha256(body.encode()).hexdigest(),
            )
        )
    return rows


def current_metrics(paths):
    rows = [row for path in paths for row in metrics(path)]
    for row in rows:
        row["file"] = str(Path(row["file"]).relative_to(ROOT))
    return rows


def revision_metrics(revision):
    paths = run("git", "ls-tree", "-r", "--name-only", revision, "--", "scripts").splitlines()
    rows = []
    for path in paths:
        if not path.endswith(".py"):
            continue
        source = run("git", "show", revision + ":" + path)
        # Historical top-level scripts are read, never executed or exempted.
        tree = ast.parse(source)
        visitor = Functions()
        visitor.visit(tree)
        for name, node in visitor.functions:
            body = ast.dump(ast.Module(body=node.body, type_ignores=[]), include_attributes=False)
            rows.append(dict(file=path, identity=name, bodyHash=hashlib.sha256(body.encode()).hexdigest()))
    return rows
