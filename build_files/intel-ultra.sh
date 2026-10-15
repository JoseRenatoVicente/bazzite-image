#!/bin/bash

set -euox pipefail

# Fedora equivalents of the NixOS Intel graphics/compute and NPU stack.
# Keep Bazzite's kernel and signed out-of-tree modules; do not replace them
# with another kernel or build v4l2loopback against the build host's kernel.
INTEL_PACKAGES=(
    microcode_ctl
    intel-gpu-firmware
    intel-npu-firmware
    intel-audio-firmware
    alsa-sof-firmware
    libva-intel-media-driver
    libva-utils
    libvpl
    intel-vpl-gpu-rt
    intel-compute-runtime
    clinfo
    intel-npu-driver
)

dnf5 install -y --setopt=install_weak_deps=False "${INTEL_PACKAGES[@]}"
rpm -q --quiet "${INTEL_PACKAGES[@]}" intel-opencl intel-level-zero \
    v4l2loopback kmod-v4l2loopback

# system_files are copied before this script runs. The optional S4 workaround
# must be executable for systemd-sleep, but is inert without the local opt-in.
chmod 0755 /usr/lib/systemd/system-sleep/latitude-lpss-s4.sh

# The exported Bazzite image has /root -> var/roothome without the /var target.
# dracut needs that directory's metadata. Supply an empty build-only directory,
# without replacing the symlink or shipping root's mutable home in the image.
roothome=/var/roothome
temporary_roothome=0
cleanup_roothome() {
    if [[ "$temporary_roothome" -eq 1 ]]; then
        rmdir "$roothome"
    fi
}
trap cleanup_roothome EXIT
if [[ -L /root && "$(readlink /root)" == var/roothome && ! -e "$roothome" ]]; then
    mkdir -m 0700 "$roothome"
    temporary_roothome=1
fi

# Build a generic initramfs for the IMAGE kernel, never `uname -r` (the host).
# Merely shipping a dracut drop-in would leave the base image's prebuilt
# initramfs unchanged. Do not bake in the build host's root/resume arguments.
kernels=0
for kernel_dir in /usr/lib/modules/*; do
    [[ -f "$kernel_dir/vmlinuz" ]] || continue
    kver="${kernel_dir##*/}"
    modinfo -k "$kver" intel_vpu >/dev/null
    modinfo -k "$kver" v4l2loopback >/dev/null
    # Rootless builders cannot preserve security xattrs. They are not stored
    # in the initramfs's newc archive anyway; keep this scoped to the build.
    # Use the Containerfile's tmpfs rather than the image's /var/tmp overlay.
    dracut_log=$(mktemp /tmp/dracut-intel-ultra.XXXXXX)
    DRACUT_NO_XATTR=1 dracut --force --no-hostonly --no-hostonly-cmdline \
        --tmpdir /tmp --kver "$kver" "$kernel_dir/initramfs.img" \
        2>&1 | tee "$dracut_log"
    # Some dracut-install failures do not propagate to dracut's exit status.
    # Never accept a partially generated image just because it is nonempty.
    if grep -E '^dracut(\[[EF]\]:|-install: ERROR:)' "$dracut_log" >&2; then
        echo "ERROR: initramfs generation reported errors for $kver" >&2
        exit 1
    fi
    rm -f "$dracut_log"
    [[ -s "$kernel_dir/initramfs.img" ]]
    early_drivers=$(lsinitrd --file etc/cmdline.d/20-force_drivers.conf \
        "$kernel_dir/initramfs.img")
    for driver in i915 thunderbolt dm_snapshot; do
        if ! grep -Fx "rd.driver.pre=$driver" <<<"$early_drivers" >/dev/null; then
            echo "ERROR: initramfs does not preload $driver for $kver" >&2
            exit 1
        fi
    done
    initrd_modules=$(lsinitrd --mod "$kernel_dir/initramfs.img")
    for module in ostree resume; do
        if ! grep -Fx "$module" <<<"$initrd_modules" >/dev/null; then
            echo "ERROR: initramfs is missing $module support for $kver" >&2
            exit 1
        fi
    done
    kernels=$((kernels + 1))
done

if [[ "$kernels" -eq 0 ]]; then
    echo "ERROR: no bootable image kernel found in /usr/lib/modules" >&2
    exit 1
fi
