#!/bin/bash

set -ouex pipefail

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
    # CJK fonts and Asian input methods (ibus itself must stay: plasma-desktop
    # links against libibus)
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
    # fcitx5 language engines (fcitx5 core, qt/gtk and configtool stay)
    fcitx5-chewing
    fcitx5-chinese-addons
    fcitx5-chinese-addons-data
    fcitx5-hangul
    fcitx5-m17n
    fcitx5-mozc
    fcitx5-sayura
    fcitx5-table-extra
    fcitx5-unikey
    libchewing
    libhangul
    libime
    libime-data
    m17n-db
    m17n-db-devel
    m17n-lib
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
    # Intel OpenCL compute runtime (video, games and Vulkan are not affected)
    intel-opencl
    intel-opencl-clang
    intel-igc
    intel-igc-libs
    llvm15-libs
    clang15-libs
    lld15-libs
    'spirv-llvm15*'
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
    atheros-firmware
    mt7xxx-firmware
    amd-gpu-firmware
    # Misc
    tesseract-devel
    fish
)

# Matched by the patterns above but must stay
KEEP_PACKAGES=(
    qemu-system-x86
    qemu-system-x86-core
    edk2-ovmf
    edk2-tools
)

to_remove=()
for pattern in "${REMOVE_PATTERNS[@]}"; do
    mapfile -t matches < <(rpm -qa --qf '%{NAME}\n' "$pattern" | sort -u \
        | grep -vxF "$(printf '%s\n' "${KEEP_PACKAGES[@]}")" || true)
    if [ "${#matches[@]}" -eq 0 ]; then
        echo "WARNING: no installed package matches '$pattern', skipping"
    else
        to_remove+=("${matches[@]}")
    fi
done

if [ "${#to_remove[@]}" -gt 0 ]; then
    # Fail closed: the whole set must be removable without breaking any package
    # that is NOT in the set. If a base update makes something in the list a
    # dependency of the desktop, the build stops here instead of removing it.
    rpm -e --test "${to_remove[@]}"
    # --no-autoremove: only drop what is listed above. Autoremove would also
    # pull in unrelated "unused" packages (git, lxc, gamescope-session-steam...).
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
dnf5 install -y tmux

# Use a COPR Example:
#
# dnf5 -y copr enable ublue-os/staging
# dnf5 -y install package
# Disable COPRs so they don't end up enabled on the final image:
# dnf5 -y copr disable ublue-os/staging

#### Example for enabling a System Unit File

systemctl enable podman.socket

### Trim files that are not worth their size (pt_BR/en only)

# Translations other than en/pt. Not packaged separately, so rpm -V will report
# them missing; that is expected.
find /usr/share/locale -mindepth 1 -maxdepth 1 -type d \
    ! -name 'en*' ! -name 'pt*' -exec rm -rf {} +
# Emoji dictionaries for other languages (ibus itself must stay)
find /usr/share/ibus/dicts -type f -name 'emoji-*.dict' \
    ! -name 'emoji-en*' ! -name 'emoji-pt*' -delete
# Package docs (man pages and licenses are kept)
rm -rf /usr/share/doc

### Cleanup

# dnf leaves per-repo state (countme) in /var, which bootc lint flags
rm -rf /var/lib/dnf/repos
