#!/usr/bin/env bash
set -e

# ==============================================================================
# Cashon Debian (.deb) Build Script
# ==============================================================================

BOLD="\033[1m"
GREEN="\033[1;32m"
BLUE="\033[1;34m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
RESET="\033[0m"

APP_NAME="cashon"
VERSION="1.0.0"
ARCH="amd64"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo -e "${BOLD}${BLUE}====================================================${RESET}"
echo -e "${BOLD}${BLUE}             Cashon Debian (.deb) Builder           ${RESET}"
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

# Step 2: Build Debian archive
echo -e "\n${BLUE}[2/2] Packaging Debian .deb...${RESET}"
PKG_DIR="$(mktemp -d /tmp/deb-cashon-XXXXXX)"
DIST_DIR="$ROOT_DIR/dist"
mkdir -p "$DIST_DIR"

# 2.1 debian-binary
echo "2.0" > "$PKG_DIR/debian-binary"

# 2.2 Control tarball
mkdir -p "$PKG_DIR/control_dir"
cat << CTRL > "$PKG_DIR/control_dir/control"
Package: ${APP_NAME}
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: ${ARCH}
Depends: libgtk-3-0, libc6
Maintainer: Vignesh Balaji <0836balaji@gmail.com>
Description: Cashon - Personal finance and budget manager
 Cashon is an easy-to-use personal finance manager that helps you
 track expenses, manage budgets, and visualize your financial habits.
Homepage: https://git.hl.rhaegarsystems.com/VigneshBalaji/Cashon
CTRL

tar -czf "$PKG_DIR/control.tar.gz" -C "$PKG_DIR/control_dir" control

# 2.3 Data tarball
mkdir -p "$PKG_DIR/data_dir/usr/lib/cashon" \
         "$PKG_DIR/data_dir/usr/bin" \
         "$PKG_DIR/data_dir/usr/share/applications" \
         "$PKG_DIR/data_dir/usr/share/icons/hicolor/512x512/apps"

cp -r "$ROOT_DIR/build/linux/x64/release/bundle/"* "$PKG_DIR/data_dir/usr/lib/cashon/"
ln -s /usr/lib/cashon/budget "$PKG_DIR/data_dir/usr/bin/cashon"

install -m644 "$ROOT_DIR/packaging/flatpak/com.budget.tracker_app.desktop" "$PKG_DIR/data_dir/usr/share/applications/com.budget.tracker_app.desktop"
install -m644 "$ROOT_DIR/packaging/flatpak/icon-512.png" "$PKG_DIR/data_dir/usr/share/icons/hicolor/512x512/apps/com.budget.tracker_app.png"

tar -czf "$PKG_DIR/data.tar.gz" -C "$PKG_DIR/data_dir" usr

# 2.4 Assemble .deb package
OUT_FILE="$DIST_DIR/${APP_NAME}_${VERSION}_${ARCH}.deb"
(cd "$PKG_DIR" && ar rcs "$OUT_FILE" debian-binary control.tar.gz data.tar.gz)
rm -rf "$PKG_DIR"

echo -e "\n${BOLD}${GREEN}====================================================${RESET}"
echo -e "${BOLD}${GREEN}               DEBIAN BUILD COMPLETE!               ${RESET}"
echo -e "${BOLD}${GREEN}====================================================${RESET}"
echo -e "Output file: ${BOLD}${OUT_FILE}${RESET} ($(du -h "$OUT_FILE" | awk '{print $1}'))"
echo -e "Install on Ubuntu/Debian via:"
echo -e "    ${BOLD}${YELLOW}sudo dpkg -i ${OUT_FILE}${RESET}\n"
