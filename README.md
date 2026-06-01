# falco-py-pre-commit

A pip-installable [`falco`](https://github.com/ysugimoto/falco) binary (the
Fastly VCL developer tool / linter), packaged as [pre-commit](https://pre-commit.com)
hooks.

Modelled on [shellcheck-py](https://github.com/shellcheck-py/shellcheck-py):
there is no Go toolchain or `brew` involved. When pre-commit installs a hook
from this repo it builds the package in an isolated virtualenv, and
[`setuptools-download`](https://pypi.org/project/setuptools-download/) fetches
the correct pre-built `falco` binary for the current platform (verified by
SHA256) into that venv.

## Requirements

- Network access to GitHub Releases the first time a hook is installed.
- A supported platform: **macOS or Linux, x86_64 or arm64**. Falco ships no
  Windows build, so these hooks cannot run on native Windows (WSL is fine).

## Usage

Add to your `.pre-commit-config.yaml`:

```yaml
repos:
  - repo: https://github.com/gadventures/falco-py-pre-commit
    rev: v2.3.0
    hooks:
      - id: falco-lint-all-changed
```

> Pinning `rev: v2.3.0` pins Falco itself to v2.3.0 for everyone on the team.

### Hooks

| id | what it does | filenames |
|----|--------------|-----------|
| `falco-lint-all-changed` | Runs `falco lint` **once per changed `.vcl` file** (see note below) and fails if any file has errors. | passed (`*.vcl`) |
| `falco` | Generic escape hatch — runs the raw `falco` binary with whatever `args:` you supply (`lint` a single entrypoint, `fmt`, `test`, `stats`, …). | not passed |
| `falco-version` | Diagnostic/CI helper — runs `falco --version` unconditionally. Handy for pinning-assertion checks in CI. | not passed |

#### Why `falco-lint-all-changed` instead of plain `falco lint`?

`falco lint` only ever processes the **first** file argument and silently
ignores the rest. Since pre-commit batches all matched files into one
invocation, a naive `entry: falco lint` would lint only the first changed
file and let the others pass unchecked. The `falco-lint-all-changed` hook wraps
`falco` and invokes it once per file, OR-ing the exit codes, so every changed
`.vcl` is actually linted.

By default it lints each file with include paths `-I <file's dir> -I .`. Only
**errors** fail the commit; warnings pass (run the generic `falco` hook with
`-v`/`-vv` if you want to surface those).

#### VCL with `include`s

Per-file linting is correct for **self-contained** `.vcl` files. If your VCL is
split across `include`d fragments, an edited fragment is not independently
valid on its own. For those projects, use the generic `falco` hook in
single-entrypoint mode instead:

```yaml
repos:
  - repo: https://github.com/gadventures/falco-py-pre-commit
    rev: v2.3.0
    hooks:
      - id: falco
        args: [lint, -I, ., src/main.vcl]
```

This lints the whole project from `src/main.vcl` (resolving includes from `-I`
paths) whenever any `.vcl` file changes.

### Other falco subcommands

The generic `falco` hook can run anything the binary supports, e.g. checking
formatting:

```yaml
      - id: falco
        name: falco fmt (check)
        args: [fmt, --fix=false, -I, ., src/main.vcl]
```

## Updating the bundled Falco version

Each release of this package pins one upstream Falco release. The package
version mirrors the Falco version; a packaging-only change against the same
Falco release appends a fourth segment (e.g. `2.3.0.1`).

To bump Falco:

```bash
bin/update-falco.sh v2.4.0
```

This downloads the four release archives and prints a ready-to-paste
`[setuptools_download]` block. Then:

1. Replace the `[setuptools_download]` block in `setup.cfg` with the output.
2. Bump `version` in `setup.cfg` to match (e.g. `2.4.0`).
3. `git commit -am "falco 2.4.0"`
4. `git tag v2.4.0 && git push --tags`
5. Consumers bump `rev:` in their config (or run `pre-commit autoupdate`).

## Development

Two scriptable checks, neither needing a global install:

```bash
# Full regression test: builds into a throwaway venv (downloads + SHA256-verifies
# the pinned falco binary) and asserts the hook works -- including that a bad
# file is caught even when it is NOT the first argument.
./testing/smoke-test.sh

# Ecosystem-standard "installable + runs" check (mirrors shellcheck-py):
uvx tox
```

`testing/smoke-test.sh` reads the expected falco version from `setup.cfg`, so it
keeps passing after `bin/update-falco.sh` bumps the pin. It builds from a
temporary copy of the working tree, so it never leaves `build/` or `*.egg-info`
behind in the repo. `uvx tox` can't assert the failure path (any non-zero
command is a tox failure), which is why the shell script carries the full
assertion set.

## Notes

- The installed command is `falco`. If you `pip install` this package into a
  shared environment, that name can collide with a globally-installed Falco or
  the unrelated [CNCF `falco`](https://falco.org) runtime-security tool. Inside
  pre-commit's isolated per-hook venv this is a non-issue, and the
  `falco-lint-all-changed` wrapper always calls *its own* bundled binary, never
  whatever `falco` is on `$PATH`.

## Why not use `language: golang`?

pre-commit v3+ can build hooks from Go source with `language: golang`, which
on the face of it should let us drop the prebuilt-binary + platform-wheel
machinery and just `go install` the pinned falco tag. There's a couple blockers
that make `go install`-ing `ysugimoto/falco` difficult today:

1. **Upstream's `go.mod` at v2+ tags declares `module github.com/ysugimoto/falco`
   with no `/v2` suffix**, which violates Go's semver-import-path rule.
   `go install github.com/ysugimoto/falco/cmd/falco@v2.3.0` (and the
   `.../falco/v2/cmd/falco@v2.3.0` variant) both fail with
   `invalid version: module contains a go.mod file, so module path must match
   major version`. Upstream [PR #615](https://github.com/ysugimoto/falco/pull/615)
   fixes the module path, but only helps tags cut *after* it merges — every
   existing v2.x.y release stays uninstallable.
2. **Pinning by commit SHA (a Go pseudo-version) can sidestep rule 1** — the
   pseudo-version starts `v0.0.0-…` so the v2+ rule doesn't apply — but falco's
   `go.mod` uses `replace` directives, and Go ignores `replace` directives from
   dependency modules (they only apply when the module is *main*). `go install
   github.com/ysugimoto/falco/cmd/falco@<sha>` fail to resolve the `replace`.

Because it's tricky to build it ourselves, we just pull the pre-built binaries
from GitHub releases.

## License

MIT. Falco itself is MIT-licensed by [ysugimoto](https://github.com/ysugimoto/falco).
