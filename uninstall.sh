#!/usr/bin/env bash
set -Eeuo pipefail

[[ $EUID -eq 0 ]] || { echo 'Run this uninstaller with sudo.' >&2; exit 1; }
BACKUP_DIR=${1:-}
TARGET_USER=${SUDO_USER:-}
if [[ -z $TARGET_USER && -n ${PKEXEC_UID:-} ]]; then
  TARGET_USER=$(getent passwd "$PKEXEC_UID" | cut -d: -f1)
fi
TARGET_HOME=$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6)
HYPR_AUTOSTART=${TARGET_HOME:+$TARGET_HOME/.config/hypr/autostart.conf}

systemctl disable suspend-fix-t2.service 2>/dev/null || true
systemctl disable amdgpu-off.service 2>/dev/null || true
rm -f /etc/systemd/system/suspend-fix-t2.service
rm -f /etc/systemd/system/amdgpu-off.service
rm -f /etc/systemd/sleep.conf.d/10-macbook-s2idle.conf
rm -f /etc/limine-entry-tool.d/t2-suspend.conf
rm -f /etc/modprobe.d/apple-gmux.conf
rm -f /etc/udev/rules.d/30-amdgpu-pm.rules

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
  restore /etc/modprobe.d/apple-gmux.conf
  restore /etc/udev/rules.d/30-amdgpu-pm.rules
  restore /etc/systemd/system/amdgpu-off.service
  [[ -n $HYPR_AUTOSTART ]] && restore "$HYPR_AUTOSTART"
else
  # Remove only the exact legacy stanza written by this project. Never strip
  # pm_async=off from Omarchy's distribution-managed T2 kernel parameters.
  sed -i '/^# Required by the T2 Linux setup guide; keep asynchronous device suspend off\.$/{N;/\nKERNEL_CMDLINE\[default\]+=" pm_async=off"$/d;}' /etc/default/limine
  if [[ -n $HYPR_AUTOSTART && -f $HYPR_AUTOSTART ]]; then
    sed -i '/^# t2-macbook-balanced-power$/,/^# end-t2-macbook-balanced-power$/d' "$HYPR_AUTOSTART"
  fi
  printf 'No backup directory supplied; the current fan configuration was preserved.\n'
fi

systemctl daemon-reload
systemctl disable fstrim.timer 2>/dev/null || true
systemctl restart t2fanrd.service 2>/dev/null || true
limine-mkinitcpio
printf 'Workaround removed. Reboot required.\n'
