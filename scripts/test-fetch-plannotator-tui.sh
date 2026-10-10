#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
plugin_root="$test_root/plugin root with spaces"
source_root="$test_root/source binary with spaces"
mkdir -p "$plugin_root/scripts" "$plugin_root/bin" "$source_root"
cp "$repository_root/scripts/fetch-plannotator-tui.sh" "$plugin_root/scripts/"
cp "$repository_root/scripts/plannotator-tui.sh" "$plugin_root/scripts/"
cp "$repository_root/plannotator-tui.version" "$plugin_root/"

source_binary="$source_root/plannotator-tui local"
cat > "$source_binary" <<'EOF'
#!/usr/bin/env sh
printf 'plannotator-tui 0.9.4-herdr.1\n'
EOF
chmod +x "$source_binary"
printf 'old destination' > "$plugin_root/bin/plannotator-tui.exe"
chmod +x "$plugin_root/bin/plannotator-tui.exe"
printf 'old-version' > "$plugin_root/bin/plannotator-tui.version"

PLANNOTATOR_TUI_BIN="$source_binary" bash "$plugin_root/scripts/fetch-plannotator-tui.sh"
cmp "$source_binary" "$plugin_root/bin/plannotator-tui.exe"
test "$(cat "$plugin_root/bin/plannotator-tui.version")" = 0.9.4-herdr.1
test ! -e "$plugin_root/bin/plannotator-tui"
test "$("$plugin_root/bin/plannotator-tui.exe" --version)" = "plannotator-tui 0.9.4-herdr.1"
test "$(bash "$plugin_root/scripts/plannotator-tui.sh" --version)" = "plannotator-tui 0.9.4-herdr.1"

output="$(bash "$plugin_root/scripts/fetch-plannotator-tui.sh")"
case "$output" in
  *"already installed"*) ;;
  *) echo "idempotent fetch did not short-circuit: $output" >&2; exit 1 ;;
esac

# Downloaded fork assets are installed only after verification. Failed verification leaves
# both an existing runtime and its version stamp intact.
fixture="$test_root/release"
fake_bin="$test_root/fake-bin"
mkdir -p "$fixture" "$fake_bin"
case "$(uname -s)/$(uname -m)" in
  Darwin/arm64) target=aarch64-apple-darwin ;;
  Darwin/x86_64) target=x86_64-apple-darwin ;;
  Linux/x86_64) target=x86_64-unknown-linux-gnu ;;
  Linux/aarch64|Linux/arm64) target=aarch64-unknown-linux-gnu ;;
esac
asset="plannotator-tui-$target"
cp "$source_binary" "$fixture/$asset"
if command -v sha256sum >/dev/null 2>&1; then
  checksum="$(sha256sum "$fixture/$asset" | awk '{print $1}')"
else
  checksum="$(shasum -a 256 "$fixture/$asset" | awk '{print $1}')"
fi
printf '%s  %s\n' "$checksum" "$asset" > "$fixture/SHA256SUMS"
cat > "$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
set -eu
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) destination="$2"; shift 2 ;;
    --retry) shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
cp "$FETCH_FIXTURE/${url##*/}" "$destination"
EOF
chmod +x "$fake_bin/curl"
printf 'old-version' > "$plugin_root/bin/plannotator-tui.version"
FETCH_FIXTURE="$fixture" PATH="$fake_bin:$PATH" bash "$plugin_root/scripts/fetch-plannotator-tui.sh"
cmp "$source_binary" "$plugin_root/bin/plannotator-tui.exe"
printf 'older-version' > "$plugin_root/bin/plannotator-tui.version"
printf 'bad-checksum  %s\n' "$asset" > "$fixture/SHA256SUMS"
if FETCH_FIXTURE="$fixture" PATH="$fake_bin:$PATH" bash "$plugin_root/scripts/fetch-plannotator-tui.sh" 2>"$test_root/checksum.err"; then
  echo "bad checksum exited successfully" >&2; exit 1
fi
grep -q "sha256 mismatch" "$test_root/checksum.err"
cmp "$source_binary" "$plugin_root/bin/plannotator-tui.exe"
test "$(cat "$plugin_root/bin/plannotator-tui.version")" = older-version
