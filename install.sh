#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
MODEL=$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)
FORCE=${1:-}

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || die "Required command not found: $1"; }

[[ $EUID -eq 0 ]] || die "Run this installer with sudo."
[[ $MODEL == MacBookPro16,1 || $FORCE == --force ]] || \
  die "Detected '$MODEL', not MacBookPro16,1. Refusing to continue."

for command in install systemctl modprobe rmmod limine-mkinitcpio; do need "$command"; done
modinfo apple-bce >/dev/null 2>&1 || die "apple-bce is unavailable; install a T2-enabled kernel first."

if ! zgrep -q '^CONFIG_MODULE_FORCE_UNLOAD=y' /proc/config.gz 2>/dev/null; then
  die "The running kernel does not advertise CONFIG_MODULE_FORCE_UNLOAD=y."
fi

STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR=/var/backups/t2-macbook-suspend-fix/$STAMP
mkdir -p "$BACKUP_DIR"

backup() {
  local path=$1 name=${1#/}
  if [[ -e $path ]]; then
    install -D -m 0644 "$path" "$BACKUP_DIR/$name"
  else
    install -D -m 0644 /dev/null "$BACKUP_DIR/$name.absent"
  fi
}

backup /etc/systemd/system/suspend-fix-t2.service
backup /etc/systemd/sleep.conf.d/10-macbook-s2idle.conf
backup /etc/limine-entry-tool.d/t2-suspend.conf
backup /etc/default/limine
backup /etc/t2fand.conf

install -D -m 0644 "$ROOT_DIR/files/suspend-fix-t2.service" \
  /etc/systemd/system/suspend-fix-t2.service
install -D -m 0644 "$ROOT_DIR/files/10-macbook-deep.conf" \
  /etc/systemd/sleep.conf.d/10-macbook-s2idle.conf
install -D -m 0644 "$ROOT_DIR/files/t2-suspend.conf" \
  /etc/limine-entry-tool.d/t2-suspend.conf
install -D -m 0644 "$ROOT_DIR/files/t2fand.conf" /etc/t2fand.conf

[[ -f /etc/default/limine ]] || die "/etc/default/limine is missing."
if ! grep -q 'pm_async=off' /etc/default/limine; then
  printf '%s\n' 'KERNEL_CMDLINE[default]+=" pm_async=off"' >> /etc/default/limine
fi

systemctl daemon-reload
systemctl enable suspend-fix-t2.service
systemctl restart t2fanrd.service
limine-mkinitcpio

printf '\nInstalled successfully.\nBackup: %s\nReboot, run ./verify.sh, then test lid-close suspend.\n' "$BACKUP_DIR"
