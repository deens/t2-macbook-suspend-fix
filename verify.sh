#!/usr/bin/env bash
set -u

failures=0
check() {
  local description=$1; shift
  if "$@" >/dev/null 2>&1; then
    printf 'PASS  %s\n' "$description"
  else
    printf 'FAIL  %s\n' "$description"
    failures=$((failures + 1))
  fi
}

printf 'Model:  %s\n' "$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo unknown)"
printf 'Kernel: %s\n\n' "$(uname -r)"

check 'correct MacBook model is detected' grep -qx MacBookPro16,1 /sys/class/dmi/id/product_name
for package in linux-t2 linux-t2-headers apple-t2-audio-config apple-bcm-firmware \
  t2fanrd tiny-dfr thermald power-profiles-daemon; do
  check "$package package is installed" pacman -Q "$package"
done
check 'apple-bce module is available' modinfo apple-bce
check 'apple-bce is loaded' grep -qw apple_bce /proc/modules
check 'forced module unloading is enabled' sh -c "zgrep -q '^CONFIG_MODULE_FORCE_UNLOAD=y' /proc/config.gz"
check 'Intel IOMMU is enabled' grep -qw intel_iommu=on /proc/cmdline
check 'IOMMU passthrough is enabled' grep -qw iommu=pt /proc/cmdline
check 'suspend workaround is enabled' systemctl is-enabled suspend-fix-t2.service
check 'suspend unit passes static validation' systemd-analyze verify /etc/systemd/system/suspend-fix-t2.service
check 'running kernel has pm_async=off' grep -qw pm_async=off /proc/cmdline
check 'pm_async=off occurs only once' sh -c "test \"\$(tr ' ' '\n' < /proc/cmdline | grep -cx pm_async=off)\" -eq 1"
check 'deep sleep is selected by systemd' grep -q '^MemorySleepMode=deep' /etc/systemd/sleep.conf.d/10-macbook-s2idle.conf
check 'Fan1 is configured' grep -q '^\[Fan1\]' /etc/t2fand.conf
check 'Fan2 is configured' grep -q '^\[Fan2\]' /etc/t2fand.conf
check 'fan daemon is active' systemctl is-active t2fanrd.service
check 'Touch Bar daemon is active' systemctl is-active tiny-dfr.service
check 'thermal daemon is active' systemctl is-active thermald.service
check 'power profiles daemon is active' systemctl is-active power-profiles-daemon.service
check 'balanced power profile is active' sh -c "test \"\$(powerprofilesctl get)\" = balanced"
check 'weekly SSD trim is enabled' systemctl is-enabled fstrim.timer
check 'balanced Fan1 curve is configured' sh -c "awk '/^\\[Fan1\\]/{fan=1;next} /^\\[/{fan=0} fan&&/^low_temp=50$/{low=1} fan&&/^high_temp=80$/{high=1} END{exit !(low&&high)}' /etc/t2fand.conf"
check 'balanced Fan2 curve is configured' sh -c "awk '/^\\[Fan2\\]/{fan=1;next} /^\\[/{fan=0} fan&&/^low_temp=50$/{low=1} fan&&/^high_temp=80$/{high=1} END{exit !(low&&high)}' /etc/t2fand.conf"
check 'internal keyboard and trackpad are present' sh -c "find /dev/input/by-id -maxdepth 1 -iname '*Internal_Keyboard*' | grep -q ."
check 'Touch Bar is present' sh -c "find /dev/input/by-id -maxdepth 1 -iname '*Touch_Bar*' | grep -q ."
check 'keyboard backlight is present' test -e /sys/class/leds/:white:kbd_backlight
check 'display backlight is present' test -e /sys/class/backlight/gmux_backlight
check 'internal audio driver is present' test -e /sys/bus/pci/drivers/aaudio
check 'internal camera is present' test -e /dev/video0
check 'internal Wi-Fi is present' test -e /sys/class/net/wlan0
check 'Bluetooth controller is present' test -e /sys/class/bluetooth/hci0
check 'battery is present' test -e /sys/class/power_supply/BAT0
check 'unsafe apple-gmux override is absent' test ! -e /etc/modprobe.d/apple-gmux.conf
check 'unsafe Radeon-off service is absent' test ! -e /etc/systemd/system/amdgpu-off.service
check 'stale Radeon power rule is absent' test ! -e /etc/udev/rules.d/30-amdgpu-pm.rules

if [[ -r /sys/class/power_supply/BAT0/power_now ]]; then
  awk '{printf "Battery power: %.1f W\n", $1 / 1000000}' /sys/class/power_supply/BAT0/power_now
elif [[ -r /sys/class/power_supply/BAT0/current_now && -r /sys/class/power_supply/BAT0/voltage_now ]]; then
  awk -v current="$(cat /sys/class/power_supply/BAT0/current_now)" \
    -v voltage="$(cat /sys/class/power_supply/BAT0/voltage_now)" \
    'BEGIN {printf "Battery power: %.1f W\n", current * voltage / 1000000000000}'
fi

printf '\n'
if ((failures)); then
  printf '%d check(s) failed. Do not test suspend until they are resolved.\n' "$failures"
  exit 1
fi
printf 'All configuration checks passed.\n'
