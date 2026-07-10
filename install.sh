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

for command in install pacman systemctl modprobe rmmod limine-mkinitcpio; do need "$command"; done

# Omarchy normally installs these during T2 hardware detection. Keep the
# finishing kit self-contained for reinstalls and repair any missing package
# without refreshing package databases or performing a full system upgrade.
pacman -S --needed --noconfirm \
  linux-t2 \
  linux-t2-headers \
  apple-t2-audio-config \
  apple-bcm-firmware \
  t2fanrd \
  tiny-dfr \
  thermald \
  power-profiles-daemon

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
backup /etc/modprobe.d/apple-gmux.conf
backup /etc/udev/rules.d/30-amdgpu-pm.rules
backup /etc/systemd/system/amdgpu-off.service

install -D -m 0644 "$ROOT_DIR/files/suspend-fix-t2.service" \
  /etc/systemd/system/suspend-fix-t2.service
install -D -m 0644 "$ROOT_DIR/files/10-macbook-deep.conf" \
  /etc/systemd/sleep.conf.d/10-macbook-s2idle.conf
install -D -m 0644 "$ROOT_DIR/files/t2fand.conf" /etc/t2fand.conf

# Releases containing the experimental hybrid-graphics setup could page-fault
# in apple_gmux during boot and leave the internal panel black. Remove those
# files when upgrading while preserving the suspend and fan configuration.
systemctl disable --now amdgpu-off.service 2>/dev/null || true
rm -f /etc/systemd/system/amdgpu-off.service
rm -f /etc/modprobe.d/apple-gmux.conf
rm -f /etc/udev/rules.d/30-amdgpu-pm.rules

[[ -f /etc/default/limine ]] || die "/etc/default/limine is missing."
# Migrate the line written by releases before hybrid-graphics support. Omarchy's
# own T2 line is left untouched. Use our drop-in only when no other config owns
# the parameter, which keeps the generated kernel command line deduplicated.
sed -i '/^# Required by the T2 Linux setup guide; keep asynchronous device suspend off\.$/{N;/\nKERNEL_CMDLINE\[default\]+=" pm_async=off"$/d;}' /etc/default/limine
if grep -Rqs --include='*.conf' --exclude='t2-suspend.conf' -w 'pm_async=off' \
  /etc/limine-entry-tool.d || grep -qw 'pm_async=off' /etc/default/limine; then
  rm -f /etc/limine-entry-tool.d/t2-suspend.conf
else
  install -D -m 0644 "$ROOT_DIR/files/t2-suspend.conf" \
    /etc/limine-entry-tool.d/t2-suspend.conf
fi

systemctl daemon-reload
systemctl enable suspend-fix-t2.service
systemctl enable t2fanrd.service
systemctl enable tiny-dfr.service
systemctl enable thermald.service
systemctl enable power-profiles-daemon.service
systemctl restart t2fanrd.service
limine-mkinitcpio

printf '\nInstalled successfully.\nBackup: %s\n' "$BACKUP_DIR"
printf 'Reboot, run ./verify.sh, then test lid-close suspend.\n'
printf 'If upgrading from the hybrid-graphics release, reboot is required to restore the display path.\n'
