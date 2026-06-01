"""falco-py-pre-commit: a pip-installable, pre-commit-ready falco binary.

The actual `falco` binary is downloaded at build/install time by
``setuptools-download`` (see setup.cfg). This package only contains the thin
wrapper used by the ``falco-lint-all-changed`` hook.
"""
