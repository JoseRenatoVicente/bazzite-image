#!/bin/bash

set -euox pipefail

# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /

### Remove packages we don't use (reduces the size of the deployed system)

# Patterns are expanded against the installed set, so a package that the base
# image drops in the future only produces a warning instead of breaking the build.
REMOVE_PATTERNS=(
    # AMD ROCm / compute stack (Intel-only hardware)
    'rocm-*'
    amdsmi
    hipcc
    # NVIDIA firmware (no NVIDIA GPU)
    nvidia-gpu-firmware
    # MariaDB server and KDE PIM database backend
    mariadb-server
    mariadb-backup
    mariadb-gssapi-server
    mariadb-cracklib-password-check
    mariadb
    akonadi-server
    akonadi-server-mysql
    # Handheld / console-mode extras
    opengamepadui
    gamescope-session-ogui-steam
    godot-runner
    waydroid
    waydroid-selinux
    steamdeck-dsp
    steamdeck-kde-presets
    # Bazzite handheld/Steam QoL tools
    bpftune-gaming
    gmodpatchtool
    cardwire-gui
    cardwire
    # Steam and the gaming-session stack (Terra gamescope build). Removing
    # Steam also unlocks dropping every i686 (32-bit) package below.
    steam
    'steam-libs*'
    steam-devices
    steam-notif-daemon
    gamescope-session-steam
    gamescope-session
    'terra-gamescope*'
    ScopeBuddy
    'terra-mangohud*'
    # Remaining gaming overlays/capture hooks (vulkan-tools stays: kinfocenter)
    vkBasalt
    vulkan-low-latency-layer
    'obs-studio-plugin-vkcapture*'
    # CJK fonts and Asian input methods
    # (the ibus daemon goes too: its only remaining requirers were the engines
    # below; ibus-libs stays because plasma-desktop links against it)
    'google-noto-*cjk*'
    'default-fonts-cjk-*'
    anthy-unicode
    kasumi-unicode
    kasumi-common
    ibus-anthy
    ibus-anthy-python
    libpinyin
    libpinyin-data
    ibus-pinyin
    ibus-table
    ibus-table-chinese
    ibus-table-chinese-cangjie
    ibus-table-chinese-quick
    ibus-libpinyin
    ibus-hangul
    ibus-chewing
    ibus-m17n
    ibus-typing-booster
    cldr-emoji-annotation
    cldr-emoji-annotation-dtd
    unicode-ucd
    # ibus daemon (orphan after the engines above are gone)
    ibus
    ibus-setup
    ibus-panel
    ibus-gtk3
    ibus-gtk4
    python3-ibus
    # Orphaned AWS Python SDK
    python3-boto3
    python3-s3transfer
    python3-botocore
    # VM / hypervisor guest agents (bare metal)
    open-vm-tools-desktop
    spice-vdagent
    spice-webdavd
    hyperv-daemons
    qemu-guest-agent
    virtualbox-guest-additions
    # Steam Deck hardware support, unused 3D/Qt leftovers, misc tools
    jupiter-hw-support-btrfs
    embree
    python3-pyside6
    sos
    words
    pinfo
    lrzsz
    # Wallpapers
    plasma-workspace-wallpapers
    # Fcitx input-method stack (the desktop keyboard layout is configured by KDE)
    'fcitx5*'
    kcm-fcitx5
    libchewing
    libhangul
    libime
    libime-data
    m17n-db
    m17n-db-devel
    m17n-lib
    # sched-ext schedulers (Bazzite gaming CPU schedulers, unused)
    scx-scheds
    scx-tools
    # KDE WebEngine stack (~300 MB): python3-pyside6 and fcitx5-chinese-addons,
    # removed above, were the other requirers. signon-plugin-oauth2 stays:
    # plasma-desktop requires it directly. qt6-qtpositioning/qt6-qtwebsockets
    # also stay (plasma-workspace-libs / qcoro).
    qt6-qtwebengine
    qt6-qtwebchannel
    qt6-qtwebview
    kaccounts-providers
    kio-gdrive
    khelpcenter
    plasma-nm-openconnect
    kdeplasma-addons
    signon-ui
    # WebKit app bundles: Bazaar (GNOME app store; Discover is kept) and Lutris
    webkitgtk6.0
    javascriptcoregtk6.0
    bazaar
    webkit2gtk4.1
    javascriptcoregtk4.1
    lutris
    # Non-x86 emulation and firmware (x86 KVM, virt-manager and OVMF stay,
    # see KEEP_PACKAGES). qemu is an empty meta that requires every qemu-system-*
    qemu
    'qemu-system-*'
    'qemu-user*'
    'edk2-*'
    # Docker (podman stays)
    docker-ce
    docker-ce-cli
    containerd.io
    docker-buildx-plugin
    docker-compose-plugin
    # Extra tools
    cosign
    tailscale
    podman-tui
    guestfs-tools
    makemkv
    glow
    gdb
    gdb-headless
    debugedit
    flatpak-builder
    stress-ng
    # eBPF diagnostics and their LLVM 21 runtime. llvm-libs stays for Mesa.
    bcc
    bcc-tools
    python3-bcc
    bpftrace
    clang21-libs
    llvm21-libs
    # Intel OpenCL compute runtime (video, games and Vulkan are not affected)
    intel-opencl
    intel-opencl-clang
    intel-igc
    intel-igc-libs
    llvm15-libs
    clang15-libs
    lld15-libs
    'spirv-llvm15*'
    # Legacy Intel Media SDK (VAAPI and intel-vpl-gpu-rt stay for Meteor Lake)
    intel-mediasdk
    # Kernel headers (gcc stays: perl -> perl-ExtUtils-CBuilder requires it)
    kernel-devel
    kernel-devel-matched
    # Accessibility (flite stays: webkit and qt6-qtspeech link against it)
    orca
    brltty
    speech-dispatcher
    speech-dispatcher-espeak-ng
    espeak-ng
    # Oxygen theme
    oxygen-icon-theme
    plasma-oxygen
    oxygen-cursor-themes
    oxygen-sounds
    # Printer drivers (hplip-libs/libgs stay: sane and ghostscript need them)
    hplip
    uld
    gutenprint
    gutenprint-cups
    gutenprint-libs
    # Firmware for hardware this machine does not have
    # (Intel Wi-Fi iwlwifi-*, realtek and core linux-firmware stay)
    atheros-firmware
    mt7xxx-firmware
    amd-gpu-firmware
    brcmfmac-firmware
    tiwilink-firmware
    libertas-firmware
    qcom-wwan-firmware
    iwlegacy-firmware
    nxpwireless-firmware
    # Legacy sound firmware (modern SOF stack stays)
    alsa-firmware
    alsa-tools-firmware
    # Editors (vi/vim-minimal stays)
    kate
    kate-plugins
    kate-krunner-plugin
    vim-enhanced
    vim-common
    # glibc all-langpacks: en/pt langpacks are installed before removal (below)
    glibc-all-langpacks
    # OCR language data for languages we don't read (eng/por kept, see KEEP)
    tesseract
    'tesseract-langpack-*'
    # OpenConnect VPN backend (the Plasma plugin above is removed with it)
    openconnect
    NetworkManager-openconnect
    # Braille translation chain (rest of the accessibility debloat)
    liblouis
    liblouis-tables
    python3-louis
    liblouisutdml
    liblouisutdml-utils
    braille-printer-app
    # Orphans and dead weight from the base image
    gettext
    python3-rapidfuzz
    bison
    elfutils
    openssl-devel
    openbios
    gnome-desktop3
    plasma-oxygen-qt6
    plasma-oxygen-qt5
    lato-fonts
    adwaita-mono-fonts
    nerd-fonts
    # Static serif variants; variable Noto Serif and other serif fonts stay
    google-noto-serif-fonts
    mariadb-errmsg
    # Misc
    tesseract-devel
    fish
)

# Matched by the patterns above but must stay
KEEP_PACKAGES=(
    # Backup/sync tools are explicitly required
    rclone
    restic
    # Unowned Bazzite power-profile scripts call the Qt 4 qdbus command
    qt
    qemu-system-x86
    qemu-system-x86-core
    edk2-ovmf
    edk2-tools
    # tesseract langpacks we actually use; tesseract-libs stays because
    # spectacle (OCR in screenshots) and libavfilter link against it
    tesseract-langpack-eng
    tesseract-langpack-por
)

# glibc-all-langpacks (227 MB) -> glibc-langpack-en + glibc-langpack-pt (~10 MB,
# "pt" covers pt_BR). The install MUST happen before the removal test: glibc
# requires at least one "glibc-langpack" provider to be installed.
dnf5 install -y glibc-langpack-en glibc-langpack-pt

to_remove=()
for pattern in "${REMOVE_PATTERNS[@]}"; do
    # Emit full NEVRA: multilib packages exist in two arches under the same
    # NAME, and rpm -e (used for the fail-closed test below) refuses ambiguous
    # name-only specs.
    while IFS= read -r nevra; do
        [[ -z "$nevra" ]] && continue
        keep=0
        for k in "${KEEP_PACKAGES[@]}"; do
            [[ "$nevra" == "$k"-* ]] && keep=1
        done
        if ((keep)); then
            continue
        fi
        to_remove+=("$nevra")
    done < <(rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' "$pattern" 2>/dev/null | sort -u)
    if ! rpm -qa --qf '%{NAME}\n' "$pattern" 2>/dev/null | grep -q .; then
        echo "WARNING: no installed package matches '$pattern', skipping"
    fi
done

# Multilib i686: with Steam gone nothing hard-requires 32-bit packages,
# so every i686 package goes. Selected by NEVRA because the pattern loop
# above matches package NAMES only (the arch is not part of the name).
mapfile -t i686_nevras < <(rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' | grep '\.i686$' || true)
to_remove+=("${i686_nevras[@]}")

# Dedup: the same package can match several patterns (guard against the
# empty case, which would produce a single empty element below)
if [ "${#to_remove[@]}" -gt 0 ]; then
    readarray -t to_remove < <(printf '%s\n' "${to_remove[@]}" | sort -u)
fi

if [ "${#to_remove[@]}" -gt 0 ]; then
    # Fail closed: the whole set must be removable without breaking any package
    # that is NOT in the set. If a base update makes something in the list a
    # dependency of the desktop, the build stops here instead of removing it.
    rpm -e --test "${to_remove[@]}"
    # --no-autoremove: only drop what is listed above. Autoremove would also
    # pull in unrelated "unused" packages (git, lxc, rclone, restic, ...).
    dnf5 remove -y --no-autoremove "${to_remove[@]}"

    # Verify nothing from the list is left behind
    for pkg in "${to_remove[@]}"; do
        if rpm -q --quiet "$pkg"; then
            echo "ERROR: $pkg is still installed after removal" >&2
            exit 1
        fi
    done
fi

### Install packages

# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/43/x86_64/repoview/index.html&protocol=https&redirect=1

# this installs a package from fedora repos
dnf5 install -y --setopt=install_weak_deps=False tmux rclone restic

# Enforce the explicitly retained tools even if a future base drops them.
rpm -q --quiet rclone restic

# Use a COPR Example:
#
# dnf5 -y copr enable ublue-os/staging
# dnf5 -y install package
# Disable COPRs so they don't end up enabled on the final image:
# dnf5 -y copr disable ublue-os/staging

#### Example for enabling a System Unit File

systemctl enable podman.socket

### Keep Vulkan drivers for the Intel workstation and virtualization

# Mesa bundles these drivers in one RPM, so remove the unused libraries and
# their loader manifests together. Intel/HasVK, Lavapipe and VirtIO stay.
UNUSED_VULKAN_DRIVERS=(
    radeon
    nouveau
    panfrost
    asahi
    freedreno
    powervr_mesa
    broadcom
)
for driver in "${UNUSED_VULKAN_DRIVERS[@]}"; do
    rm -f "/usr/lib64/libvulkan_${driver}.so" \
        "/usr/share/vulkan/icd.d/${driver}_icd.x86_64.json"
done

# Fail the build if a base/package change removed a driver we still need.
for driver in intel lvp virtio; do
    if [[ ! -s "/usr/lib64/libvulkan_${driver}.so" || \
        ! -s "/usr/share/vulkan/icd.d/${driver}_icd.x86_64.json" ]]; then
        echo "ERROR: required Vulkan driver '$driver' is missing" >&2
        exit 1
    fi
done

### Trim files that are not worth their size (pt_BR/en only)

# Translations other than en/pt. Not packaged separately, so rpm -V will report
# them missing; that is expected.
find /usr/share/locale -mindepth 1 -maxdepth 1 -type d \
    ! -name 'en*' ! -name 'pt*' -exec rm -rf {} +
# Emoji dictionaries for other languages (harmless: the dicts are data files)
# The dict dir disappears together with ibus; guard it so errexit isn't tripped
if [ -d /usr/share/ibus/dicts ]; then
    find /usr/share/ibus/dicts -type f -name 'emoji-*.dict' \
        ! -name 'emoji-en*' ! -name 'emoji-pt*' -delete
fi
# Qt translations (.qm): English is the source language, pt is kept
for d in /usr/share/qt6/translations /usr/share/qt5/translations; do
    if [ -d "$d" ]; then
        find "$d" -type f -name '*.qm' ! -name '*pt*' -delete
    fi
done
# VS Code UI locales other than en/pt (Electron .pak files)
if [ -d /usr/share/code/locales ]; then
    find /usr/share/code/locales -type f -name '*.pak' \
        ! -name 'en-*' ! -name 'pt-*' -delete
fi
# Package docs, man pages and wallpapers (licenses are kept)
rm -rf /usr/share/doc /usr/share/man /usr/share/wallpapers
# Bundled Bazzite documentation (HTML copy + launcher, unowned by rpm)
rm -rf /usr/share/ublue-os/docs
rm -f /usr/share/applications/bazzite-documentation.desktop

### Cleanup

# dnf leaves per-repo state (countme) in /var, which bootc lint flags
rm -rf /var/lib/dnf/repos

# Big dnf transactions leave a huge sqlite WAL (~100+ MB) in the rpmdb.
# Flush it, then switch to DELETE journaling so RPM queries work on a read-only
# deployment without needing to create WAL/shared-memory files alongside it.
python3 - <<'PY'
import sqlite3

db = sqlite3.connect("file:/usr/share/rpm/rpmdb.sqlite?mode=rw", uri=True)
try:
    checkpoint = db.execute("PRAGMA wal_checkpoint(TRUNCATE)").fetchone()
    if checkpoint[0] != 0:
        raise RuntimeError("RPM database WAL checkpoint is busy")
    mode = db.execute("PRAGMA journal_mode=DELETE").fetchone()[0]
    if mode.lower() != "delete":
        raise RuntimeError(f"Unexpected RPM database journal mode: {mode}")
finally:
    db.close()
PY
