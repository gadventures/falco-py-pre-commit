"""Wrapper entry point for the ``falco-lint-all-changed`` pre-commit hook.

Why this exists: ``falco lint`` only ever processes the *first* file argument
and silently ignores the rest. pre-commit batches all matched files into a
single invocation, so ``falco lint a.vcl b.vcl c.vcl`` would lint only
``a.vcl`` and let the others pass unchecked -- a silent false "pass".

This wrapper instead runs ``falco lint`` once per file and OR's the exit codes
together, so every changed ``.vcl`` is actually linted.
"""

from __future__ import annotations

import os
import subprocess
import sys


def _falco_binary() -> str:
    """Return the path to the falco binary bundled in *this* environment.

    setuptools-download installs the ``falco`` binary into the same scripts
    directory as this wrapper -- i.e. the pre-commit hook's isolated venv
    ``bin/`` directory, alongside the python interpreter running us. We resolve
    it explicitly and deliberately do NOT fall back to ``$PATH`` so we never
    shell out to some *other* ``falco`` (a globally-installed version, or the
    unrelated CNCF ``falco`` runtime-security tool).
    """
    candidates = [
        # The venv bin dir (where sys.executable lives) -- the reliable answer.
        os.path.join(os.path.dirname(os.path.abspath(sys.executable)), "falco"),
        # Belt-and-suspenders: alongside this wrapper's own console script.
        os.path.join(os.path.dirname(os.path.abspath(sys.argv[0])), "falco"),
    ]
    for candidate in candidates:
        if os.path.isfile(candidate):
            return candidate
    raise SystemExit(
        "falco-lint-all-changed: could not find the bundled `falco` binary "
        f"(looked in {', '.join(repr(c) for c in candidates)}). "
        "The falco-py-pre-commit package may not have installed correctly.",
    )


def main(argv: list[str] | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    falco = _falco_binary()

    returncode = 0
    for filename in argv:
        # Add include paths so same-directory and repo-root includes resolve.
        include_paths: list[str] = []
        for path in (os.path.dirname(filename), "."):
            path = path or "."
            if path not in include_paths:
                include_paths.append(path)

        cmd = [falco, "lint"]
        for path in include_paths:
            cmd += ["-I", path]
        cmd.append(filename)

        returncode |= subprocess.call(cmd)

    return returncode


if __name__ == "__main__":
    raise SystemExit(main())
