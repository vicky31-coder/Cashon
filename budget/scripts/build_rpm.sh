#!/usr/bin/env bash
set -e

# ==============================================================================
# Cashon RPM (.rpm) Build Script
# ==============================================================================

BOLD="\033[1m"
GREEN="\033[1;32m"
BLUE="\033[1;34m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
RESET="\033[0m"

APP_NAME="cashon"
VERSION="1.0.0"
RELEASE="1"
ARCH="x86_64"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo -e "${BOLD}${BLUE}====================================================${RESET}"
echo -e "${BOLD}${BLUE}              Cashon RPM (.rpm) Builder             ${RESET}"
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

if ! command -v rpmbuild >/dev/null 2>&1; then
    echo -e "${RED}Error: 'rpmbuild' is required but not installed (install 'rpm' / 'rpm-build').${RESET}"
    exit 1
fi

# Step 2: Build RPM package
echo -e "\n${BLUE}[2/2] Packaging RPM...${RESET}"
RPM_TOPDIR="$(mktemp -d /tmp/rpm-cashon-XXXXXX)"
DIST_DIR="$ROOT_DIR/dist"
mkdir -p "$DIST_DIR" \
         "$RPM_TOPDIR/BUILD" \
         "$RPM_TOPDIR/RPMS" \
         "$RPM_TOPDIR/SOURCES" \
         "$RPM_TOPDIR/SPECS" \
         "$RPM_TOPDIR/SRPMS"

STAGE_DIR="$RPM_TOPDIR/SOURCES/${APP_NAME}-${VERSION}"
mkdir -p "$STAGE_DIR/usr/lib/cashon" \
         "$STAGE_DIR/usr/bin" \
         "$STAGE_DIR/usr/share/applications" \
         "$STAGE_DIR/usr/share/icons/hicolor/512x512/apps"

cp -r "$ROOT_DIR/build/linux/x64/release/bundle/"* "$STAGE_DIR/usr/lib/cashon/"
ln -s /usr/lib/cashon/budget "$STAGE_DIR/usr/bin/cashon"
install -m644 "$ROOT_DIR/packaging/flatpak/com.budget.tracker_app.desktop" "$STAGE_DIR/usr/share/applications/com.budget.tracker_app.desktop"
install -m644 "$ROOT_DIR/packaging/flatpak/icon-512.png" "$STAGE_DIR/usr/share/icons/hicolor/512x512/apps/com.budget.tracker_app.png"

cat << SPEC > "$RPM_TOPDIR/SPECS/${APP_NAME}.spec"
%global __brp_check_rpaths %{nil}
%global debug_package %{nil}
%define _build_id_links none

Name:           ${APP_NAME}
Version:        ${VERSION}
Release:        ${RELEASE}
Summary:        Cashon - Personal finance and budget manager
License:        GPL-3.0-or-later
URL:            https://github.com/vicky31-coder/Cashon
BuildArch:      ${ARCH}
AutoReqProv:    no
Requires:       gtk3, glibc

%description
Cashon is a personal finance and budget manager that helps you track expenses,
manage budgets, and sync across devices.

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}
cp -a ${STAGE_DIR}/* %{buildroot}/

%files
/usr/lib/cashon
/usr/bin/cashon
/usr/share/applications/com.budget.tracker_app.desktop
/usr/share/icons/hicolor/512x512/apps/com.budget.tracker_app.png
SPEC

rpmbuild --define "_topdir $RPM_TOPDIR" -bb "$RPM_TOPDIR/SPECS/${APP_NAME}.spec"

OUT_FILE="$DIST_DIR/${APP_NAME}-${VERSION}-${RELEASE}.${ARCH}.rpm"
cp "$RPM_TOPDIR/RPMS/${ARCH}/${APP_NAME}-${VERSION}-${RELEASE}.${ARCH}.rpm" "$OUT_FILE"
rm -rf "$RPM_TOPDIR"

echo -e "\n${BOLD}${GREEN}====================================================${RESET}"
echo -e "${BOLD}${GREEN}                 RPM BUILD COMPLETE!                ${RESET}"
echo -e "${BOLD}${GREEN}====================================================${RESET}"
echo -e "Output file: ${BOLD}${OUT_FILE}${RESET} ($(du -h "$OUT_FILE" | awk '{print $1}'))\n"
