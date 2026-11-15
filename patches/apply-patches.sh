#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Apply the two MT7902 kernel-compatibility patches to a
# hmtheboy154/mt7902 source tree.
#
# Usage:
#   bash apply-patches.sh [driver-source-directory]
#
# Default driver directory: current directory.
# The script is idempotent (already applied patches are skipped) and
# backs up every modified file as <file>.bak.

set -euo pipefail

SRC="$(cd "${1:-.}" && pwd)"
HERE="$(cd "$(dirname "$0")" && pwd)"

for f in src/mt76.h src/mac80211.c; do
    if [ ! -f "$SRC/$f" ]; then
        echo "error: $SRC/$f not found - is this the hmtheboy154/mt7902 tree?" >&2
        exit 1
    fi
done

if ! command -v patch >/dev/null 2>&1; then
    echo "error: 'patch' is not installed (sudo apt install patch)" >&2
    exit 1
fi

apply_one() {
    local patch_file="$1" marker="$2" target="$3" name
    name="$(basename "$patch_file")"

    if grep -qF -- "$marker" "$SRC/$target"; then
        echo "skip  $name (already applied)"
        return 0
    fi

    cp -f "$SRC/$target" "$SRC/$target.bak"

    if ( cd "$SRC" && patch -p1 --forward --batch < "$patch_file" ); then
        echo "apply $name -> $target"
    else
        cp -f "$SRC/$target.bak" "$SRC/$target"
        echo "error: $name did not apply cleanly; $target was restored" >&2
        exit 1
    fi
}

apply_one "$HERE/0001-mt76-define-rate-mask-flag.patch" \
          "#define IEEE80211_TX_CTRL_DONT_USE_RATE_MASK 0" \
          src/mt76.h

apply_one "$HERE/0002-mt76-vif-phy-fallback-without-chanctx.patch" \
          "failed to insert STA entry" \
          src/mac80211.c

echo
echo "Patches applied. Next:"
echo "  sudo make CC=gcc-12 install -j\"\$(nproc)\""
echo "  sudo make install_fw"
echo "  sudo reboot"
