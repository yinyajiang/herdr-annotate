#!/usr/bin/env bash
# Build the patched review runtime; also used when fork release assets are not published yet.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source_root="$(bash "$root/scripts/prepare-plannotator-tui.sh" "${PLANNOTATOR_TUI_SOURCE:-$root/.build/plannotator-tui}")"
cargo build --locked --manifest-path "$source_root/Cargo.toml" --release -p plannotator-tui
PLANNOTATOR_TUI_BIN="$source_root/target/release/plannotator-tui" bash "$root/scripts/fetch-plannotator-tui.sh"
