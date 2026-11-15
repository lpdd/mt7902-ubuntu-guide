#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# One-shot installer: clone the hmtheboy154/mt7902 driver, apply the
# compatibility patches from this repository, build and install it.
#
# Usage:
#   bash scripts/install.sh [driver-dir]
#
# Default driver directory: <this-repo>/mt7902
# Run as a normal user; sudo is called only for the install steps.

set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
    echo "Please run this script as a normal user (sudo is used where needed)." >&2
    exit 1
fi

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DRIVER_DIR="${1:-$REPO_DIR/mt7902}"
DRIVER_URL="https://github.com/hmtheboy154/mt7902.git"
PINNED_COMMIT="9d302626688709ebf27dda597fdbce274efecea1"

say() { printf '\n==> %s\n' "$*"; }

# --- prerequisites --------------------------------------------------------
for cmd in git make gcc-12 patch; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "error: '$cmd' not found. Install the prerequisites first:" >&2
        echo "  sudo apt update" >&2
        echo "  sudo apt install -y git build-essential gcc-12 patch \"linux-headers-\$(uname -r)\"" >&2
        exit 1
    fi
done

KVER="$(uname -r)"
if [ ! -d "/lib/modules/$KVER/build" ]; then
    echo "error: kernel headers for $KVER not found:" >&2
    echo "  sudo apt install -y linux-headers-$KVER" >&2
    echo "or, for Ubuntu HWE kernels:" >&2
    echo "  sudo apt install -y linux-headers-generic-hwe-22.04" >&2
    exit 1
fi

# --- driver source --------------------------------------------------------
if [ ! -d "$DRIVER_DIR/.git" ]; then
    say "Cloning $DRIVER_URL"
    git clone "$DRIVER_URL" "$DRIVER_DIR"
    git -C "$DRIVER_DIR" checkout "$PINNED_COMMIT"
else
    say "Using existing driver tree: $DRIVER_DIR"
fi

# --- patches --------------------------------------------------------------
say "Applying compatibility patches"
bash "$REPO_DIR/patches/apply-patches.sh" "$DRIVER_DIR"

# --- build and install ----------------------------------------------------
say "Building against kernel $KVER"
make -C "$DRIVER_DIR" CC=gcc-12 -j"$(nproc)"

say "Installing module and firmware (sudo required)"
sudo make -C "$DRIVER_DIR" CC=gcc-12 install
sudo make -C "$DRIVER_DIR" install_fw

say "Done"
echo "Reboot to load the patched module:"
echo "    sudo reboot"
echo
echo "After rebooting, verify with:"
echo "    lspci -nnk | grep -iA3 14c3"
echo "    nmcli device status"
echo "    sudo dmesg | grep -i mt7902"
