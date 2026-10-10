#!/usr/bin/env bash
# Prepare the exact upstream source plus this fork's recipient-selection patch.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
revision=59fa0af536260b54b4a6341ab306c9e6c93d9a55
archive_sha256=11e38ae317a0d0eb79cf5991f6bf77c393b0f360c365b92d5fef391965fa6ab2
destination="${1:-$root/.build/plannotator-tui}"
patch_file="$root/patches/plannotator-tui-agent-selection.patch"
checksum() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}';
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}
stamp="$revision $(checksum "$patch_file")"
if [ -f "$destination/crates/plannotator-tui/src/app/agents.rs" ] && [ -f "$destination/.herdr-annotate-source" ] && [ "$(cat "$destination/.herdr-annotate-source")" = "$stamp" ]; then
  echo "$destination"
  exit 0
fi
if [ -e "$destination" ]; then
  echo "source directory already exists with a different revision: $destination; choose an empty destination" >&2
  exit 1
fi
mkdir -p "$(dirname "$destination")"
tmp="$(mktemp -d "$(dirname "$destination")/.plannotator-source.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL --retry 3 "https://codeload.github.com/plannotator/plannotator-tui/tar.gz/$revision" -o "$tmp/source.tar.gz"
[ "$(checksum "$tmp/source.tar.gz")" = "$archive_sha256" ] || { echo "plannotator-tui source checksum mismatch" >&2; exit 1; }
mkdir "$tmp/source"
tar -xzf "$tmp/source.tar.gz" --strip-components=1 -C "$tmp/source"
# Isolate git apply from the plugin checkout: applying inside a subdirectory of another
# Git repository would silently skip paths outside that repository prefix.
(cd "$tmp/source" && git init -q && git apply --check "$patch_file" && git apply "$patch_file")
[ -f "$tmp/source/crates/plannotator-tui/src/app/agents.rs" ] || { echo "agent selection patch was not applied" >&2; exit 1; }
printf '%s' "$stamp" > "$tmp/source/.herdr-annotate-source"
mv "$tmp/source" "$destination"
echo "$destination"
