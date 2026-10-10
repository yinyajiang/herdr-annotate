#!/usr/bin/env bash
# Put the pinned plannotator-tui release into bin/. Run by Herdr as a plugin build step
# (cwd = plugin root) and by hand for local testing.
#
#   plannotator-tui.version        the release to install (one line, e.g. 0.1.0)
#   bin/plannotator-tui.exe        the binary
#   bin/plannotator-tui.version    what is installed; matching the pin means nothing to do
#
# Modes, in order:
#   1. already installed at the pinned version         -> exit 0
#   2. PLANNOTATOR_TUI_BIN=/path/to/binary is set      -> copy it (local testing, no download)
#   3. otherwise download the release asset for this platform and verify its sha256
#
# Fork releases contain the patched TUI. Before a release exists, build the pinned source
# with Rust 1.96+ and git. Failed verification never installs an unpatched review binary.
set -euo pipefail

cd "$(dirname "$0")/.."
version="$(tr -d '[:space:]' < plannotator-tui.version)"
[ -n "$version" ] || { echo "plannotator-tui.version is empty" >&2; exit 1; }
mkdir -p bin
destination="bin/plannotator-tui.exe"
stamp="bin/plannotator-tui.version"
installed="$(cat bin/plannotator-tui.version 2>/dev/null || true)"

if [ -x "$destination" ] && [ "$installed" = "$version" ] && [ -z "${PLANNOTATOR_TUI_BIN:-}" ]; then
  echo "plannotator-tui $version already installed"
  exit 0
fi

if [ -n "${PLANNOTATOR_TUI_BIN:-}" ]; then
  [ -x "$PLANNOTATOR_TUI_BIN" ] || { echo "PLANNOTATOR_TUI_BIN is not an executable: $PLANNOTATOR_TUI_BIN" >&2; exit 1; }
  rm -f "$destination"
  cp "$PLANNOTATOR_TUI_BIN" "$destination"
  chmod +x "$destination"
  printf '%s' "$version" > "$stamp"
  echo "installed plannotator-tui from $PLANNOTATOR_TUI_BIN (local build, stamped $version)"
  exit 0
fi

case "$(uname -s)/$(uname -m)" in
  Darwin/arm64)            target=aarch64-apple-darwin ;;
  Darwin/x86_64)           target=x86_64-apple-darwin ;;
  Linux/x86_64)            target=x86_64-unknown-linux-gnu ;;
  Linux/aarch64|Linux/arm64) target=aarch64-unknown-linux-gnu ;;
  *) echo "warning: no plannotator-tui build for $(uname -s)/$(uname -m); the review pane is unavailable" >&2; exit 0 ;;
esac

asset="plannotator-tui-$target"
base="${PLANNOTATOR_TUI_RELEASE_BASE:-https://github.com/yinyajiang/herdr-annotate/releases/download/tui-v$version}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fetch() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 -o "$2" "$1"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$2" "$1"
  else
    echo "need curl or wget" >&2; return 1
  fi
}

echo "downloading $base/$asset"
give_up() { echo "$1 — the review pane was not installed" >&2; exit 1; }
source_build() {
  if command -v cargo >/dev/null 2>&1 && command -v git >/dev/null 2>&1 && [ -f scripts/build-plannotator-tui.sh ]; then
    echo "fork release unavailable; building the patched review runtime from pinned source"
    bash scripts/build-plannotator-tui.sh
    exit 0
  fi
  give_up "download failed; install Rust 1.96+ and git to build locally, or retry after the fork release is published"
}
fetch "$base/$asset" "$tmp/$asset"       || source_build
fetch "$base/SHA256SUMS" "$tmp/SHA256SUMS" || give_up "download failed: $base/SHA256SUMS"

expected="$(grep " $asset\$" "$tmp/SHA256SUMS" | awk '{print $1}')"
[ -n "$expected" ] || give_up "$asset is not listed in $base/SHA256SUMS"
if command -v sha256sum >/dev/null 2>&1; then
  actual="$(sha256sum "$tmp/$asset" | awk '{print $1}')"
else
  actual="$(shasum -a 256 "$tmp/$asset" | awk '{print $1}')"
fi
[ "$actual" = "$expected" ] || give_up "sha256 mismatch for $asset: expected $expected, got $actual"

chmod +x "$tmp/$asset"
rm -f "$destination"
cp "$tmp/$asset" "$destination"
chmod +x "$destination"
printf '%s' "$version" > "$stamp"
echo "installed plannotator-tui $version ($target)"
