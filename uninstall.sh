#!/usr/bin/env bash
set -Eeuo pipefail

[[ $EUID -eq 0 ]] || { echo 'Run this uninstaller with sudo.' >&2; exit 1; }
BACKUP_DIR=${1:-}

systemctl disable suspend-fix-t2.service 2>/dev/null || true
rm -f /etc/systemd/system/suspend-fix-t2.service
rm -f /etc/systemd/sleep.conf.d/10-macbook-s2idle.conf
rm -f /etc/limine-entry-tool.d/t2-suspend.conf

if [[ -n $BACKUP_DIR ]]; then
  [[ -d $BACKUP_DIR ]] || { echo "Backup not found: $BACKUP_DIR" >&2; exit 1; }
  restore() {
    local path=$1 saved=$BACKUP_DIR/${1#/}
    if [[ -f $saved ]]; then
      install -D -m 0644 "$saved" "$path"
    elif [[ -f $saved.absent ]]; then
      rm -f "$path"
    fi
  }
  restore /etc/systemd/system/suspend-fix-t2.service
  restore /etc/systemd/sleep.conf.d/10-macbook-s2idle.conf
  restore /etc/limine-entry-tool.d/t2-suspend.conf
  restore /etc/default/limine
  restore /etc/t2fand.conf
else
  sed -i 's/[[:space:]]pm_async=off//g' /etc/default/limine
  sed -i '/^KERNEL_CMDLINE\[default\]+=""$/d' /etc/default/limine
  printf 'No backup directory supplied; the current fan configuration was preserved.\n'
fi

systemctl daemon-reload
systemctl restart t2fanrd.service 2>/dev/null || true
limine-mkinitcpio
printf 'Workaround removed. Reboot required.\n'
