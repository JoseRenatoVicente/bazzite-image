#!/bin/bash

set -euo pipefail

# The reference Latitude 7450 loses its touchpad after S4. Do not assume that
# every Core Ultra laptop (including the host's Latitude 5450) has this bug.
[[ -f /etc/bazzite-image/latitude-lpss-s4-workaround ]] || exit 0
[[ -r /sys/class/dmi/id/sys_vendor && -r /sys/class/dmi/id/product_name ]] || exit 0
[[ "$(</sys/class/dmi/id/sys_vendor)" == "Dell Inc." ]] || exit 0
case "$(</sys/class/dmi/id/product_name)" in
    "Latitude 5450" | "Latitude 7450") ;;
    *) exit 0 ;;
esac

# For suspend-then-hibernate, $2 stays "suspend-then-hibernate" across both
# stages. SYSTEMD_SLEEP_ACTION identifies the actual S4 transition, so normal
# suspend and suspend-after-failed-hibernate must not unbind the touchpad.
case "${SYSTEMD_SLEEP_ACTION:-${2:-}}" in
    hibernate | hybrid-sleep) ;;
    *) exit 0 ;;
esac

device=0000:00:15.3
pci="/sys/bus/pci/devices/$device"
driver=/sys/bus/pci/drivers/intel-lpss
state=/run/latitude-lpss-s4-unbound

[[ -r "$pci/vendor" && -r "$pci/device" ]] || exit 0
[[ "$(<"$pci/vendor")" == 0x8086 && "$(<"$pci/device")" == 0x7e7b ]] || exit 0

case "${1:-}" in
    pre)
        [[ -L "$pci/driver" && "$(readlink -f "$pci/driver")" == "$driver" ]] || exit 0
        printf '%s\n' "$device" >"$driver/unbind"
        touch "$state"
        ;;
    post)
        # Only rebind a device that this hook actually unbound.
        [[ -f "$state" ]] || exit 0
        if [[ ! -L "$pci/driver" ]]; then
            printf '%s\n' "$device" >"$driver/bind"
        fi
        rm -f "$state"
        ;;
esac
