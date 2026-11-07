"""Validate every pushed ref; preserve effective custom hooks configuration."""

import subprocess
import sys

from .common import ROOT, execute, run

ZERO = "0" * 40


def setup():
    result = subprocess.run(["git", "config", "--get", "core.hooksPath"], cwd=ROOT, text=True, capture_output=True)
    if result.returncode not in (0, 1):
        raise RuntimeError("Cannot read Git hooks configuration: " + result.stderr.strip())
    hooks = result.stdout.strip()
    if hooks and hooks != ".githooks":
        raise ValueError("Existing core.hooksPath: " + hooks + ". Integrate .githooks/pre-push; nothing overwritten.")
    execute(["git", "config", "--local", "core.hooksPath", ".githooks"])
    print("Installed repository pre-push hook. Check: scripts/check.sh; format: scripts/format.sh")


def pushed_bases(lines):
    bases = []
    head = run("git", "rev-parse", "HEAD").strip()
    for line in lines:
        local_ref, local_oid, _remote_ref, remote_oid = line.split()
        if local_oid == ZERO:
            continue
        commit = run("git", "rev-parse", local_oid + "^{commit}").strip()
        if checked_tag(local_ref, commit):
            continue
        if commit != head:
            raise ValueError("Push the checked-out branch separately so the gate validates the exact commit.")
        bases.append("origin/main" if remote_oid == ZERO else remote_oid)
    return bases


def checked_tag(reference, commit):
    if not reference.startswith("refs/tags/"):
        return False
    result = subprocess.run(
        ["git", "merge-base", "--is-ancestor", commit, "origin/main"], cwd=ROOT, capture_output=True
    )
    if result.returncode not in (0, 1):
        raise RuntimeError("Fetch origin/main before pushing this tag.")
    return result.returncode == 0


def check(lines):
    bases = pushed_bases(lines)
    if not bases:
        return
    # One common ancestor covers all pushed ranges, not merely the final ref.
    base = run("git", "merge-base", "--octopus", "HEAD", *bases).strip()
    execute(["scripts/check.sh", "--base", base, "--require-clean"])


def main():
    try:
        check(sys.stdin)
    except (ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
