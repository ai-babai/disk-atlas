"""Shell stays a thin POSIX adapter; actual decisions live in measured Python."""

import json
import subprocess

from .common import ROOT, execute

FORBIDDEN = {"IfClause", "CaseClause", "ForClause", "WhileClause", "FuncDecl", "BinaryCmd"}


def paths():
    return sorted([*(ROOT / "scripts").rglob("*.sh"), ROOT / ".githooks/pre-push"])


def node_types(value):
    if isinstance(value, dict):
        yield value.get("Type")
        for child in value.values():
            yield from node_types(child)
    elif isinstance(value, list):
        for child in value:
            yield from node_types(child)


def validate_adapter(path):
    text = path.read_text()
    if not text.startswith("#!/bin/sh\n") or len(text.splitlines()) > 12:
        raise ValueError("Use a POSIX shell adapter of at most 12 lines: " + str(path))
    parsed = subprocess.check_output(["shfmt", "--language-dialect", "posix", "--to-json"], input=text, text=True)
    if set(node_types(json.loads(parsed))) & FORBIDDEN:
        raise ValueError("Move shell branching/functions to measured Python: " + str(path))


def lint(write=False):
    files = paths()
    for path in files:
        validate_adapter(path)
    execute(["shellcheck", "--norc", "--shell=sh", "--enable=all", *files])
    execute(["shfmt", "--language-dialect", "posix", "-i", "4", "-w" if write else "-d", *files])
