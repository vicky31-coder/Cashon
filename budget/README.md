<div align="center">
  <img alt="Cashon Icon" src="promotional/icons/icon.png" width="130px" />
  <h1><b>Cashon</b></h1>
  <p><b>Modern, Private, Multiplatform Personal Finance & Budget Manager</b></p>

  <p>
    <img src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter" alt="Flutter">
    <img src="https://img.shields.io/badge/Backend-PocketBase-B8860B?logo=pocketbase" alt="PocketBase">
    <img src="https://img.shields.io/badge/Database-Drift%20SQLite-003B57?logo=sqlite" alt="SQLite">
    <img src="https://img.shields.io/badge/Platform-Linux%20%7C%20Windows%20%7C%20Android-green" alt="Platforms">
    <img src="https://img.shields.io/badge/License-GPLv3-blue.svg" alt="License">
  </p>
</div>

---

## 📌 Overview

**Cashon** is a feature-rich, beautiful personal finance and budget tracking application designed to give you complete ownership and clarity over your money. 

Originally based on Cashew, Cashon has been completely re-architected with **de-Googled, self-hosted cloud synchronization** powered by [PocketBase](https://pocketbase.io), modern **Linux desktop native integration** (with support for tiling window managers like Hyprland, i3, and Sway), and first-class distribution packages for all major Linux formats (**AppImage**, **Flatpak**, **Debian/Ubuntu**, and **Arch Linux / AUR**).

---

## 🚀 What's New in Cashon

### ☁️ Self-Hosted PocketBase Sync (De-Googled)
- **Zero Proprietary Cloud Lock-In**: Complete removal of Firebase and Google Drive dependencies.
- **Self-Hosted Backend**: Backed by a high-performance PocketBase server (`cashonbackend.hl.rhaegarsystems.com`) with instant sync, authentication tokens, and strict field schema integrity.
- **Git-Style Push & Pull**: Independent manual or automatic sync controls—push local modifications or pull cloud snapshots with one click from the Accounts page.

### 🐧 First-Class Linux Desktop Experience
- **Custom Frameless Titlebar**: Clean GTK undecorated window frame with custom modern titlebar styling.
- **Tiling Window Manager Auto-Detection**: Automatically detects tiling environments (such as **Hyprland**, **i3**, **Sway**, and **Omarchy**) and cleanly hides redundant window minimize/maximize/close buttons.
- **Impeller Graphics**: Runs with Flutter's next-generation Impeller OpenGL/Vulkan rendering backend for smooth animations and low latency.
- **Distraction-Free**: Annoying recurring cloud reminder modals and login fly-in dropdowns have been removed for a clean, uninterrupted workflow.

### 📦 Universal Linux Packaging
Native build scripts produce release artifacts ready for distribution:
- **AppImage**: Standalone executable (`.AppImage`) runnable on any Linux distribution without installation.
- **Flatpak**: Sandboxed package targeting `org.freedesktop.Platform 26.08` for bleeding-edge glibc compatibility.
- **Debian / Ubuntu**: Native `.deb` package with system desktop launcher and high-res icon integration.
- **Arch Linux / AUR**: Native `PKGBUILD` and `.pkg.tar.zst` ready for `pacman` and AUR helpers (`yay`, `paru`).

---

## ✨ Key Features

### 💸 Budget Management
- **Custom Budgets & Flexible Periods**: Create budgets for weekly, monthly, annual, or custom time periods (ideal for one-time travel or project expenses).
- **Category Spending Limits**: Configure specific spending caps per category within each budget.
- **Budget History & Comparison**: View and compare historical performance across past periods to understand spending trends.
- **Financial Goals & Savings**: Track progress toward long-term savings and loan payoffs.

### 💰 Transaction Tracking
- **Rich Transaction Types**: Supports upcoming payments, subscriptions, repeating transactions, borrowed debts, and lent credits.
- **Smart Auto-Categorization**: Custom transaction titles automatically map repeated entries to categories with memory-based suggestions.
- **Fast Search & Dynamic Filters**: Filter transactions instantly by date range, category, amount, tags, and payment accounts.
- **Batch Editing**: Long-press and multi-select transactions or budgets to edit or bulk-delete.

### 💱 Accounts & Multi-Currency
- **Multi-Account Overview**: Organize multiple checking, savings, credit, or cash accounts.
- **Live Currency Conversion**: Switch between accounts and foreign currencies on the fly with live exchange rate conversions.

### 🎨 Design & Customization
- **Material You UI**: Modern, adaptive user interface with support for dynamic theming, custom accent colors, and OLED dark mode.
- **Customizable Dashboard**: Rearrange homescreen widgets and summaries to display the financial metrics you care about most.
- **Detailed Analytics**: Interactive charts and breakdown graphs to visualize spending categories at a glance.

---

## 🛠️ Building & Packaging

### Prerequisites
- [Flutter SDK](https://flutter.dev) (v3.24+ recommended)
- `clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev` (for Linux builds)
- Optional: `flatpak`, `flatpak-builder` (for Flatpak), `makepkg` (for Arch), `dpkg` or `ar` (for Debian)

### Running in Development
```bash
cd budget
flutter run -d linux
```

### Packaging for Linux
All packaging scripts are located in `budget/scripts/` and output compiled binaries to `budget/dist/`:

```bash
cd budget

# 1. Build all 4 Linux formats (Flatpak, AppImage, Deb, Arch)
./scripts/build_linux_all.sh

# 2. Build individual formats
./scripts/build_appimage.sh   # Produces dist/Cashon-1.0.0-x86_64.AppImage
./scripts/build_deb.sh        # Produces dist/cashon_1.0.0_amd64.deb
./scripts/build_aur.sh        # Produces dist/cashon-bin-1.0.0-1-x86_64.pkg.tar.zst & AUR files
./scripts/build_flatpak.sh    # Produces dist/Cashon-1.0.0-x86_64.flatpak
```

### Installing on Linux

- **AppImage**:
  ```bash
  chmod +x dist/Cashon-1.0.0-x86_64.AppImage
  ./dist/Cashon-1.0.0-x86_64.AppImage
  ```

- **Arch Linux / Omarchy**:
  ```bash
  sudo pacman -U dist/cashon-bin-1.0.0-1-x86_64.pkg.tar.zst
  ```

- **Debian / Ubuntu**:
  ```bash
  sudo dpkg -i dist/cashon_1.0.0_amd64.deb
  ```

- **Flatpak**:
  ```bash
  flatpak install --user dist/Cashon-1.0.0-x86_64.flatpak
  flatpak run com.budget.tracker_app
  ```

---

## 📁 Project Structure

```text
Cashon/
├── budget/
│   ├── assets/              # App icon, custom fonts, and translations
│   ├── lib/
│   │   ├── database/        # Drift SQLite database tables & DAOs
│   │   ├── pages/           # App screens (Home, Accounts, Budgets, Settings)
│   │   ├── struct/          # PocketBase sync service, models, preferences
│   │   └── widgets/         # Adaptive UI widgets, custom window decorations
│   ├── linux/               # Native Linux GTK runner & CMake config
│   ├── packaging/           # Packaging manifests
│   │   ├── aur/             # Arch Linux PKGBUILD & .SRCINFO
│   │   └── flatpak/         # Flatpak manifest, metainfo, and desktop files
│   └── scripts/             # Automation scripts for multi-format packaging
└── promotional/             # Promotional banners and app icons
```

---

## 📄 License

This project is licensed under the **GNU General Public License v3.0 (GPLv3)**. See the `LICENSE` file for details.
