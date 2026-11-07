"""Install hash-pinned tools in a private venv, never into the system Python."""

import hashlib
import os
import subprocess
import sys
import venv
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def fingerprint(requirements):
    return hashlib.sha256(requirements.read_bytes() + sys.version.encode()).hexdigest()


def ensure_environment(root=ROOT):
    if not (3, 9) <= sys.version_info[:2] <= (3, 14):
        raise RuntimeError("Quality tools require Python 3.9–3.14.")
    requirements = root / "quality/requirements.txt"
    directory = root / ".build/quality-tools"
    stamp = directory / "requirements.sha256"
    expected = fingerprint(requirements)
    if stamp.exists() and stamp.read_text() == expected and (directory / "bin/python3").is_file():
        return directory
    print("Preparing private, hash-pinned quality tools…", flush=True)
    venv.EnvBuilder(with_pip=True, clear=True).create(directory)
    subprocess.run(
        [
            str(directory / "bin/python3"),
            "-m",
            "pip",
            "--isolated",
            "--disable-pip-version-check",
            "install",
            "--index-url",
            "https://pypi.org/simple",
            "--require-hashes",
            "--only-binary=:all:",
            "-r",
            str(requirements),
        ],
        check=True,
    )
    stamp.write_text(expected)
    return directory


def main():
    directory = ensure_environment()
    environment = dict(os.environ, PATH=str(directory / "bin") + os.pathsep + os.environ.get("PATH", ""))
    os.execve(
        str(directory / "bin/python3"),
        [str(directory / "bin/python3"), "-m", "scripts.quality.driver", *sys.argv[1:]],
        environment,
    )


if __name__ == "__main__":
    main()
