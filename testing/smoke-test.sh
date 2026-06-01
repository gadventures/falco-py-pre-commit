#!/usr/bin/env bash
#
# End-to-end smoke test for falco-py-pre-commit, driven through pre-commit
# itself (`pre-commit try-repo`) so we exercise the exact code path a consumer
# uses: pre-commit clones the repo, sets up its own language:python env (which
# runs the PEP 517 build, downloads + SHA256-verifies the falco binary, and
# installs it into that venv), then invokes the hook's console script.
#
# Assertions:
#   1. a clean .vcl file lints with exit 0
#   2. a bad .vcl file is detected even when it is NOT the first argument
#      (guards the "falco lint silently ignores all but the first file" bug).
#      Fixtures are numbered so 0_ok.vcl sorts before 1_bad.vcl -- the prefixes
#      exist purely to make argument order explicit.
#   3. the bundled binary reports the version pinned in setup.cfg (via the
#      `falco-version` diagnostic hook)
#
# Usage:   testing/smoke-test.sh
# Needs:   uvx (from `uv`), git, tar, and network access to GitHub Releases.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# Isolated pre-commit cache: fresh install every run (so we actually exercise
# the download + SHA256 verify path) and no interaction with the user's cache.
export PRE_COMMIT_HOME="$tmp/pc-cache"

# Snapshot the working tree into a fresh git repo so try-repo tests what's on
# disk *right now*, not just what happens to be committed in $repo's HEAD.
src="$tmp/src"
mkdir -p "$src"
( cd "$repo" && tar --exclude='./.git' --exclude='./.tox' --exclude='./build' \
    --exclude='./dist' --exclude='*.egg-info' -cf - . ) | ( cd "$src" && tar -xf - )
( cd "$src" \
    && git init -q \
    && git -c user.email=smoke@test -c user.name=smoke add -A \
    && git -c user.email=smoke@test -c user.name=smoke commit -q -m snapshot )

# ---- 1. clean file lints clean --------------------------------------------
echo ">>> try-repo: 0_ok.vcl should lint clean"
uvx pre-commit try-repo "$src" falco-lint-all-changed \
    --files "$src/testing/0_ok.vcl" \
    || fail "0_ok.vcl should lint clean (exit 0)"
echo "PASS: 0_ok.vcl lints clean"

# ---- 2. bad file caught even when not the first argument ------------------
echo ">>> try-repo: 1_bad.vcl (2nd after sort) should be caught"
if uvx pre-commit try-repo "$src" falco-lint-all-changed \
        --files "$src/testing/0_ok.vcl" "$src/testing/1_bad.vcl"; then
    fail "1_bad.vcl was not detected -- silent-ignore regression"
fi
echo "PASS: 1_bad.vcl detected even when not first"

# ---- 3. bundled binary matches version pinned in setup.cfg ----------------
expected="$(grep -oE 'releases/download/v[0-9]+\.[0-9]+\.[0-9]+' "$src/setup.cfg" \
    | head -1 | sed 's#.*/##')"
[ -n "$expected" ] || fail "could not read expected falco version from setup.cfg"

echo ">>> try-repo: falco-version should report $expected"
ver_output="$(uvx pre-commit try-repo "$src" falco-version \
    --files "$src/setup.cfg" --verbose 2>&1)" \
    || fail "falco-version invocation failed:
$ver_output"
printf '%s\n' "$ver_output" | grep -qF "$expected" \
    || fail "expected falco $expected, not found in output:
$ver_output"
echo "PASS: bundled binary reports $expected"

echo
echo "All try-repo smoke checks passed. OK"
