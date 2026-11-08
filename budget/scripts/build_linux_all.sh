#!/usr/bin/env bash
set -e

# ==============================================================================
# Cashon Master Linux Multi-Packaging Script
# Builds all 4 formats: Flatpak, AppImage, Debian (.deb), and Arch (PKGBUILD)
# ==============================================================================

BOLD="\033[1m"
GREEN="\033[1;32m"
BLUE="\033[1;34m"
YELLOW="\033[1;33m"
CYAN="\033[1;36m"
RESET="\033[0m"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo -e "${BOLD}${CYAN}====================================================${RESET}"
echo -e "${BOLD}${CYAN}      Cashon Linux Multi-Package Build Suite        ${RESET}"
echo -e "${BOLD}${CYAN}====================================================${RESET}"

SKIP_FLUTTER=false
for arg in "$@"; do
    case "$arg" in
        --skip-flutter)
            SKIP_FLUTTER=true
            ;;
    esac
done

# Step 1: Compile Flutter Linux Release binary once
if [ "$SKIP_FLUTTER" = true ] && [ -f "build/linux/x64/release/bundle/budget" ]; then
    echo -e "\n${BOLD}${BLUE}[Step 1/5] Skipping Flutter build (--skip-flutter passed)${RESET}"
else
    echo -e "\n${BOLD}${BLUE}[Step 1/5] Building Flutter Linux Release Bundle...${RESET}"
    flutter build linux --release
fi

# Step 2: Build Flatpak
echo -e "\n${BOLD}${BLUE}[Step 2/5] Packaging Flatpak (.flatpak)...${RESET}"
"$ROOT_DIR/scripts/build_flatpak.sh" --skip-flutter --no-install

# Step 3: Build AppImage
echo -e "\n${BOLD}${BLUE}[Step 3/5] Packaging AppImage (.AppImage)...${RESET}"
"$ROOT_DIR/scripts/build_appimage.sh" --skip-flutter

# Step 4: Build Debian (.deb)
echo -e "\n${BOLD}${BLUE}[Step 4/5] Packaging Debian package (.deb)...${RESET}"
"$ROOT_DIR/scripts/build_deb.sh" --skip-flutter

# Step 5: Build Arch Linux (PKGBUILD / .pkg.tar.zst)
echo -e "\n${BOLD}${BLUE}[Step 5/5] Packaging Arch Linux package (.pkg.tar.zst)...${RESET}"
"$ROOT_DIR/scripts/build_aur.sh" --skip-flutter

echo -e "\n${BOLD}${GREEN}====================================================${RESET}"
echo -e "${BOLD}${GREEN}          ALL LINUX PACKAGES BUILT!                 ${RESET}"
echo -e "${BOLD}${GREEN}====================================================${RESET}"
echo -e "Artifacts available in ${BOLD}dist/${RESET}:"
ls -lh dist/
echo ""
