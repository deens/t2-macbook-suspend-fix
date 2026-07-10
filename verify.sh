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
check 'deep sleep is selected by systemd' grep -q '^MemorySleepMode=deep' /etc/systemd/sleep.conf.d/10-macbook-s2idle.conf
check 'Fan1 is configured' grep -q '^\[Fan1\]' /etc/t2fand.conf
check 'Fan2 is configured' grep -q '^\[Fan2\]' /etc/t2fand.conf
check 'fan daemon is active' systemctl is-active t2fanrd.service

printf '\n'
if ((failures)); then
  printf '%d check(s) failed. Do not test suspend until they are resolved.\n' "$failures"
  exit 1
fi
printf 'All configuration checks passed.\n'
