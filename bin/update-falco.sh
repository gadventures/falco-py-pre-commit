#!/usr/bin/env bash
#
# Compute the SHA256 checksums for a Falco release and print a ready-to-paste
# [setuptools_download] block for setup.cfg.
#
# Usage:
#   bin/update-falco.sh v2.3.0
#
# Then, to ship the new version:
#   1. Replace the [setuptools_download] block in setup.cfg with the output.
#   2. Bump `version` in setup.cfg to match (e.g. 2.3.0). For a packaging-only
#      change against the same falco release, append a 4th segment: 2.3.0.1
#   3. git commit -am "falco 2.3.0"
#   4. git tag v2.3.0 && git push --tags
#   5. Consumers bump `rev:` in their .pre-commit-config.yaml (or run
#      `pre-commit autoupdate`).
set -euo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "usage: $0 <falco-release-tag>   e.g. $0 v2.3.0" >&2
  exit 2
fi

BASE="https://github.com/ysugimoto/falco/releases/download/${VERSION}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

sha256() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | cut -d' ' -f1
  else
    sha256sum "$1" | cut -d' ' -f1
  fi
}

# Falco ships darwin/linux x amd64/arm64 only (no Windows build).
# Map Python's platform_machine values to Falco's asset arch names:
#   linux/x86_64  -> amd64      darwin/x86_64 -> amd64
#   linux/aarch64 -> arm64      darwin/arm64  -> arm64
# Format: <sys_platform>:<platform_machine>:<falco-asset-arch>
PLATFORMS=(
  "linux:x86_64:linux-amd64"
  "linux:aarch64:linux-arm64"
  "darwin:x86_64:darwin-amd64"
  "darwin:arm64:darwin-arm64"
)

echo "[setuptools_download]"
echo "download_scripts ="
for entry in "${PLATFORMS[@]}"; do
  IFS=":" read -r plat machine asset <<<"$entry"
  file="falco-${asset}.tar.gz"
  url="${BASE}/${file}"
  curl -fsSL -o "${TMP}/${file}" "$url"
  sha="$(sha256 "${TMP}/${file}")"
  cat <<EOF
    [falco]
    group = falco-binary
    marker = sys_platform == "${plat}" and platform_machine == "${machine}"
    url = ${url}
    sha256 = ${sha}
    extract = tar
    extract_path = ./falco
EOF
done
