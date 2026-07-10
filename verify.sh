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

check 'apple-bce module is available' modinfo apple-bce
check 'forced module unloading is enabled' sh -c "zgrep -q '^CONFIG_MODULE_FORCE_UNLOAD=y' /proc/config.gz"
check 'suspend workaround is enabled' systemctl is-enabled suspend-fix-t2.service
check 'suspend unit passes static validation' systemd-analyze verify /etc/systemd/system/suspend-fix-t2.service
check 'running kernel has pm_async=off' grep -qw pm_async=off /proc/cmdline
check 'pm_async=off occurs only once' sh -c "test \"\$(tr ' ' '\n' < /proc/cmdline | grep -cx pm_async=off)\" -eq 1"
check 'deep sleep is selected by systemd' grep -q '^MemorySleepMode=deep' /etc/systemd/sleep.conf.d/10-macbook-s2idle.conf
check 'Fan1 is configured' grep -q '^\[Fan1\]' /etc/t2fand.conf
check 'Fan2 is configured' grep -q '^\[Fan2\]' /etc/t2fand.conf
check 'fan daemon is active' systemctl is-active t2fanrd.service
check 'Intel GPU is selected by apple-gmux' grep -qx Y /sys/module/apple_gmux/parameters/force_igd
check 'Radeon-off service is enabled' systemctl is-enabled amdgpu-off.service
check 'Radeon-off unit passes static validation' systemd-analyze verify /etc/systemd/system/amdgpu-off.service
check 'Radeon fallback power rule is installed' grep -q 'power_dpm_force_performance_level.*low' /etc/udev/rules.d/30-amdgpu-pm.rules
check 'internal display is connected to Intel GPU' sh -c '
  for status in /sys/class/drm/card*-*/status; do
    [ "$(cat "$status" 2>/dev/null)" = connected ] || continue
    card=${status%/*}; card=${card##*/}; card=${card%%-*}
    [ "$(cat "/sys/class/drm/$card/device/vendor" 2>/dev/null)" = 0x8086 ] && exit 0
  done
  exit 1
'

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
