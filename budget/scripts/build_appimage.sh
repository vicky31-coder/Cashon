#!/usr/bin/env bash
set -e

# ==============================================================================
# Cashon AppImage Build Script
# ==============================================================================

BOLD="\033[1m"
GREEN="\033[1;32m"
BLUE="\033[1;34m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
RESET="\033[0m"

APP_NAME="Cashon"
VERSION="${VERSION:-1.0.0}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo -e "${BOLD}${BLUE}====================================================${RESET}"
echo -e "${BOLD}${BLUE}             Cashon AppImage Builder                ${RESET}"
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
    echo -e "\n${BLUE}[1/3] Skipping Flutter build (--skip-flutter passed)${RESET}"
else
    echo -e "\n${BLUE}[1/3] Compiling Flutter Linux Release Bundle...${RESET}"
    flutter build linux --release
fi

# Step 2: Ensure appimagetool is available
echo -e "\n${BLUE}[2/3] Checking AppImage toolchain...${RESET}"
mkdir -p packaging/tools
APPIMAGETOOL="$ROOT_DIR/packaging/tools/appimagetool"

if [ ! -f "$APPIMAGETOOL" ]; then
    echo -e "${YELLOW}Downloading appimagetool...${RESET}"
    curl -L -s -o "$APPIMAGETOOL" "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"
    chmod +x "$APPIMAGETOOL"
fi
echo -e "  ✔ appimagetool ready."

# Step 3: Build AppDir & AppImage
echo -e "\n${BLUE}[3/3] Packaging AppImage...${RESET}"
APP_DIR="$(mktemp -d /tmp/appimage-cashon-XXXXXX)"
DIST_DIR="$ROOT_DIR/dist"
mkdir -p "$DIST_DIR"

chmod -R a+rX "$APP_DIR"
mkdir -p "$APP_DIR/usr/lib/cashon" \
         "$APP_DIR/usr/bin" \
         "$APP_DIR/usr/share/applications" \
         "$APP_DIR/usr/share/icons/hicolor/512x512/apps"

# Copy Flutter release bundle keeping structure intact
cp -r "$ROOT_DIR/build/linux/x64/release/bundle/"* "$APP_DIR/usr/lib/cashon/"
ln -s ../lib/cashon/budget "$APP_DIR/usr/bin/cashon"

install -m644 "$ROOT_DIR/packaging/flatpak/com.budget.tracker_app.desktop" "$APP_DIR/com.budget.tracker_app.desktop"
install -m644 "$ROOT_DIR/packaging/flatpak/com.budget.tracker_app.desktop" "$APP_DIR/usr/share/applications/com.budget.tracker_app.desktop"
install -m644 "$ROOT_DIR/packaging/flatpak/icon-512.png" "$APP_DIR/com.budget.tracker_app.png"
install -m644 "$ROOT_DIR/packaging/flatpak/icon-512.png" "$APP_DIR/usr/share/icons/hicolor/512x512/apps/com.budget.tracker_app.png"
ln -s com.budget.tracker_app.png "$APP_DIR/.DirIcon"

# AppRun entrypoint
cat << 'RUN' > "$APP_DIR/AppRun"
#!/bin/sh
SELF=$(readlink -f "$0")
HERE=${SELF%/*}
export PATH="${HERE}/usr/bin:${PATH}"
export LD_LIBRARY_PATH="${HERE}/usr/lib/cashon/lib:${LD_LIBRARY_PATH}"
exec "${HERE}/usr/lib/cashon/budget" "$@"
RUN
chmod a+rx "$APP_DIR/AppRun"
chmod -R a+rX "$APP_DIR"

OUT_FILE="$DIST_DIR/${APP_NAME}-${VERSION}-x86_64.AppImage"
rm -f "$OUT_FILE"
ARCH=x86_64 "$APPIMAGETOOL" --appimage-extract-and-run "$APP_DIR" "$OUT_FILE"
rm -rf "$APP_DIR"

echo -e "\n${BOLD}${GREEN}====================================================${RESET}"
echo -e "${BOLD}${GREEN}               APPIMAGE BUILD COMPLETE!             ${RESET}"
echo -e "${BOLD}${GREEN}====================================================${RESET}"
echo -e "Output file: ${BOLD}${OUT_FILE}${RESET} ($(du -h "$OUT_FILE" | awk '{print $1}'))"
echo -e "Run directly via:"
echo -e "    ${BOLD}${YELLOW}${OUT_FILE}${RESET}\n"
