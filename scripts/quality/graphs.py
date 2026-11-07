"""Dependency-cycle and source-layer checks."""

import ast
import importlib.util
import json
import re

from .common import ROOT, run


def visit(node, graph, active, done):
    if node in active:
        raise ValueError("Circular dependency: " + " -> ".join([*active, node]))
    if node in done:
        return
    for child in graph.get(node, []):
        visit(child, graph, [*active, node], done)
    done.add(node)


def validate(graph):
    done = set()
    for target in graph:
        visit(target, graph, [], done)
    return graph


def swift_targets():
    package = json.loads(run("swift", "package", "dump-package"))
    graph = {
        target["name"]: [next(iter(dep.values()))[0] for dep in target["dependencies"]] for target in package["targets"]
    }
    forbidden = re.compile(r"^\s*(?:@testable\s+)?import\s+(AppKit|SwiftUI|DiskAtlas|AtlasCLI)\b", re.MULTILINE)
    for path in (ROOT / "Sources/AtlasCore").glob("*.swift"):
        if forbidden.search(path.read_text()):
            raise ValueError("Core must not depend on GUI/CLI: " + str(path.relative_to(ROOT)))
    return validate(graph)


def imported_names(node, package):
    if isinstance(node, ast.Import):
        return [alias.name for alias in node.names]
    if not isinstance(node, ast.ImportFrom):
        return []
    base = importlib.util.resolve_name("." * node.level + (node.module or ""), package) if node.level else node.module
    return [base, *(base + "." + alias.name for alias in node.names)]


def python_modules(paths):
    modules = {".".join(path.relative_to(ROOT).with_suffix("").parts).removesuffix(".__init__"): path for path in paths}
    graph = {}
    for module, path in modules.items():
        package = module if path.stem == "__init__" else module.rpartition(".")[0]
        names = [name for node in ast.walk(ast.parse(path.read_text())) for name in imported_names(node, package)]
        graph[module] = sorted(set(names).intersection(modules))
        if "scripts.tests" not in module and any(name.startswith("scripts.tests") for name in names):
            raise ValueError("Production scripts cannot import tests: " + module)
    return validate(graph)
