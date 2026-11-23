#!/usr/bin/env bash
set -e

# ==============================================================================
# Cashon Flatpak Build & Packaging Script
# Fast, self-contained Flatpak builder using existing Platform runtime
# ==============================================================================

BOLD="\033[1m"
GREEN="\033[1;32m"
BLUE="\033[1;34m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
RESET="\033[0m"

APP_ID="com.budget.tracker_app"
APP_NAME="Cashon"
VERSION="${VERSION:-1.0.0}"
RUNTIME_VER="${RUNTIME_VER:-24.08}"

# Locate workspace root
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo -e "${BOLD}${BLUE}====================================================${RESET}"
echo -e "${BOLD}${BLUE}       Cashon Flatpak Packaging & Installer         ${RESET}"
echo -e "${BOLD}${BLUE}====================================================${RESET}"

SKIP_FLUTTER=false
SKIP_INSTALL=false

for arg in "$@"; do
    case "$arg" in
        --skip-flutter)
            SKIP_FLUTTER=true
            ;;
        --no-install)
            SKIP_INSTALL=true
            ;;
    esac
done

# Step 1: Toolchain Validation
echo -e "\n${BLUE}[1/5] Checking Toolchain...${RESET}"
for tool in flutter flatpak; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo -e "${RED}Error: '$tool' is required but not installed.${RESET}"
        exit 1
    fi
    echo -e "  ✔ Found $tool"
done

# Step 2: Ensure Freedesktop Runtime is present
echo -e "\n${BLUE}[2/5] Checking Freedesktop Platform Runtime...${RESET}"
if ! flatpak list --runtime | grep -q "org.freedesktop.Platform.*${RUNTIME_VER}"; then
    echo -e "${YELLOW}Platform ${RUNTIME_VER} not found. Checking installed runtimes...${RESET}"
    INSTALLED_VER=$(flatpak list --runtime | grep "org.freedesktop.Platform" | awk '{print $4}' | head -n1)
    if [ -n "$INSTALLED_VER" ]; then
        echo -e "  ✔ Using installed Platform version: ${INSTALLED_VER}"
        RUNTIME_VER="$INSTALLED_VER"
    else
        echo -e "${YELLOW}Downloading org.freedesktop.Platform//${RUNTIME_VER}...${RESET}"
        flatpak install --user -y flathub "org.freedesktop.Platform//${RUNTIME_VER}"
    fi
else
    echo -e "  ✔ org.freedesktop.Platform//${RUNTIME_VER} is ready (No extra SDK download needed!)"
fi

# Step 3: Flutter Linux Release Build
if [ "$SKIP_FLUTTER" = true ] && [ -f "build/linux/x64/release/bundle/budget" ]; then
    echo -e "\n${BLUE}[3/5] Skipping Flutter build (--skip-flutter passed and binary exists)${RESET}"
else
    echo -e "\n${BLUE}[3/5] Compiling Flutter Linux Release Bundle...${RESET}"
    flutter build linux --release
fi

if [ ! -f "build/linux/x64/release/bundle/budget" ]; then
    echo -e "${RED}Error: Release bundle binary not found at build/linux/x64/release/bundle/budget${RESET}"
    exit 1
fi
echo -e "  ✔ Release bundle ready."

# Ensure 512x512 app icon exists
if [ ! -f "packaging/flatpak/icon-512.png" ]; then
    echo -e "  Generating 512x512 app icon..."
    python3 -c "from PIL import Image; img = Image.open('assets/icon/icon.png'); img.resize((512, 512), Image.Resampling.LANCZOS).save('packaging/flatpak/icon-512.png')" 2>/dev/null || cp assets/icon/icon.png packaging/flatpak/icon-512.png
fi

# Step 4: Build Flatpak Sandbox & Export Bundle
echo -e "\n${BLUE}[4/5] Packaging Flatpak Sandbox...${RESET}"
BUILD_DIR="build/flatpak-build"
REPO_DIR="build/flatpak-repo"
DIST_DIR="dist"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$REPO_DIR" "$DIST_DIR"

# Initialize sandbox directly with Platform runtime (bypasses heavy Sdk download)
flatpak build-init "$BUILD_DIR" "$APP_ID" org.freedesktop.Platform org.freedesktop.Platform "$RUNTIME_VER"

# Populate sandbox files
mkdir -p "$BUILD_DIR/files/share/cashon" \
         "$BUILD_DIR/files/bin" \
         "$BUILD_DIR/files/share/applications" \
         "$BUILD_DIR/files/share/icons/hicolor/512x512/apps" \
         "$BUILD_DIR/files/share/metainfo"

cp -r build/linux/x64/release/bundle/* "$BUILD_DIR/files/share/cashon/"
install -m755 packaging/flatpak/cashon.sh "$BUILD_DIR/files/bin/cashon"
install -m644 packaging/flatpak/com.budget.tracker_app.desktop "$BUILD_DIR/files/share/applications/com.budget.tracker_app.desktop"
install -m644 packaging/flatpak/icon-512.png "$BUILD_DIR/files/share/icons/hicolor/512x512/apps/com.budget.tracker_app.png"
install -m644 packaging/flatpak/com.budget.tracker_app.metainfo.xml "$BUILD_DIR/files/share/metainfo/com.budget.tracker_app.metainfo.xml"

# Finalize permissions
flatpak build-finish "$BUILD_DIR" \
    --command=cashon \
    --socket=wayland \
    --socket=fallback-x11 \
    --share=ipc \
    --device=dri \
    --share=network \
    --filesystem=xdg-documents \
    --filesystem=xdg-download

# Export to OSTree repository
flatpak build-export "$REPO_DIR" "$BUILD_DIR" "$RUNTIME_VER"

# Export single-file standalone .flatpak bundle
BUNDLE_OUT="${DIST_DIR}/${APP_NAME}-${VERSION}-x86_64.flatpak"
echo -e "\n${BLUE}[4.1] Creating Standalone Distributable Bundle: ${BUNDLE_OUT}...${RESET}"
flatpak build-bundle "$REPO_DIR" "$BUNDLE_OUT" "$APP_ID" "$RUNTIME_VER"
echo -e "  ✔ Standalone bundle created: ${GREEN}${BUNDLE_OUT}${RESET} ($(du -h "$BUNDLE_OUT" | awk '{print $1}'))"

# Step 5: Install locally for testing
if [ "$SKIP_INSTALL" = false ]; then
    echo -e "\n${BLUE}[5/5] Installing Flatpak locally for current user...${RESET}"
    flatpak install --user -y --reinstall "$BUNDLE_OUT"
    echo -e "  ✔ Successfully installed into your user applications!"
else
    echo -e "\n${BLUE}[5/5] Skipping local install (--no-install passed)${RESET}"
fi

echo -e "\n${BOLD}${GREEN}====================================================${RESET}"
echo -e "${BOLD}${GREEN}               BUILD COMPLETE!                      ${RESET}"
echo -e "${BOLD}${GREEN}====================================================${RESET}"
echo -e "Standalone bundle for publishing: ${BOLD}${BUNDLE_OUT}${RESET}"
echo -e "To launch and test the app right now, run:"
echo -e "    ${BOLD}${YELLOW}flatpak run ${APP_ID}${RESET}\n"
