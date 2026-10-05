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
)

to_remove=()
for pattern in "${REMOVE_PATTERNS[@]}"; do
    mapfile -t matches < <(rpm -qa --qf '%{NAME}\n' "$pattern" | sort -u)
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

### Cleanup

# dnf leaves per-repo state (countme) in /var, which bootc lint flags
rm -rf /var/lib/dnf/repos
