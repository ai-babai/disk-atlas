"""Shared structural constraints, with no new script debt baseline."""

import collections

from .coverage_audit import identity


def complexity_failures(current, legacy, policy):
    errors, debt = [], []
    for item in current:
        if item["cyclomatic"] <= policy["cyclomatic_max"] and item["cognitive"] <= policy["cognitive_max"]:
            continue
        known = legacy.get(identity(item))
        label = (
            f"{item['file']}:{item['start']} {item['identity']} CC={item['cyclomatic']} cognitive={item['cognitive']}"
        )
        if known and known["bodyHash"] == item["bodyHash"]:
            debt.append(label)
        else:
            errors.append(label)
    return errors, debt


def clone_failures(current, previous):
    clones = collections.defaultdict(list)
    for item in current:
        if item["end"] - item["start"] >= 8:
            clones[item["bodyHash"]].append(item)
    errors = []
    for group in clones.values():
        changed = any(previous.get(identity(row), {}).get("bodyHash") != row["bodyHash"] for row in group)
        if len(group) > 1 and changed:
            errors.append(
                "New exact function-body duplication: "
                + ", ".join(row["file"] + ":" + str(row["start"]) for row in group)
            )
    return errors


def file_failures(paths, maximum):
    return [str(path) + ": exceeds file line limit" for path in paths if len(path.read_text().splitlines()) > maximum]
