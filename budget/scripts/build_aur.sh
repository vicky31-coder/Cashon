#!/usr/bin/env bash
set -e

# ==============================================================================
# Cashon Arch Linux (AUR / PKGBUILD) Build Script
# ==============================================================================

BOLD="\033[1m"
GREEN="\033[1;32m"
BLUE="\033[1;34m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
RESET="\033[0m"

APP_NAME="cashon-bin"
VERSION="1.0.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo -e "${BOLD}${BLUE}====================================================${RESET}"
echo -e "${BOLD}${BLUE}       Cashon Arch Linux (PKGBUILD) Builder         ${RESET}"
echo -e "${BOLD}${BLUE}====================================================${RESET}"

SKIP_FLUTTER=false
for arg in "$@"; do
    case "$arg" in
        --skip-flutter)
            SKIP_FLUTTER=true
            ;;
    esac
done

# Step 1: Ensure Flutter release build exists
if [ "$SKIP_FLUTTER" = true ] && [ -f "build/linux/x64/release/bundle/budget" ]; then
    echo -e "\n${BLUE}[1/2] Skipping Flutter build (--skip-flutter passed)${RESET}"
else
    echo -e "\n${BLUE}[1/2] Compiling Flutter Linux Release Bundle...${RESET}"
    flutter build linux --release
fi

# Step 2: Build Arch Linux package with makepkg
echo -e "\n${BLUE}[2/2] Packaging Arch Linux package with makepkg...${RESET}"
AUR_DIR="$ROOT_DIR/packaging/aur"
DIST_DIR="$ROOT_DIR/dist"
mkdir -p "$DIST_DIR" "$AUR_DIR"

# Ensure 512x512 icon and desktop file are in packaging/aur
cp "$ROOT_DIR/packaging/flatpak/com.budget.tracker_app.desktop" "$AUR_DIR/"
cp "$ROOT_DIR/packaging/flatpak/icon-512.png" "$AUR_DIR/"

# Create source tarball from bundle
(cd "$ROOT_DIR/build/linux/x64/release/bundle" && tar -czf "$AUR_DIR/cashon-${VERSION}-linux-x64.tar.gz" .)

# Build package
(
    cd "$AUR_DIR"
    rm -rf pkg src *.pkg.tar.zst
    makepkg -f --nodeps
    makepkg --printsrcinfo > .SRCINFO
    mv *.pkg.tar.zst "$DIST_DIR/"
    rm -f "cashon-${VERSION}-linux-x64.tar.gz"
)

OUT_FILE="$DIST_DIR/${APP_NAME}-${VERSION}-1-x86_64.pkg.tar.zst"
echo -e "\n${BOLD}${GREEN}====================================================${RESET}"
echo -e "${BOLD}${GREEN}               ARCH BUILD COMPLETE!                 ${RESET}"
echo -e "${BOLD}${GREEN}====================================================${RESET}"
echo -e "Output file: ${BOLD}${OUT_FILE}${RESET} ($(du -h "$OUT_FILE" | awk '{print $1}'))"
echo -e "AUR Metadata: ${BOLD}packaging/aur/PKGBUILD${RESET} and ${BOLD}packaging/aur/.SRCINFO${RESET}"
echo -e "Install on Arch / Omarchy via:"
echo -e "    ${BOLD}${YELLOW}sudo pacman -U ${OUT_FILE}${RESET}\n"
