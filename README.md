# T2 MacBookPro16,1 Suspend Fix for Arch Linux

A reproducible workaround for T2 MacBooks that enter suspend on lid close but
never wake, plus a correction for the dual-fan configuration on the 2019
16-inch MacBook Pro.

## Target system

This repository is intentionally conservative. The installer only runs on:

- Apple `MacBookPro16,1` (16-inch, 2019)
- Arch Linux or an Arch-derived distribution using systemd
- A T2-enabled kernel with the `apple-bce` module
- A Limine/mkinitcpio boot setup such as Omarchy

The files may be useful for other Intel T2 Macs, but the automated installer
refuses other models unless `--force` is supplied.

## Why suspend fails

Apple firmware shipped with macOS Sonoma broke S3 suspend on T2 Macs. On an
affected system, the journal ends at either:

```text
PM: suspend entry (deep)
```

or:

```text
PM: suspend entry (s2idle)
```

The T2 Linux project identifies `apple-bce`, the bridge used by the internal
keyboard, trackpad, audio, and Touch Bar, as the component that must be unloaded
before sleep. This repository implements their Arch/systemd workaround and the
additional Touch Bar reinitialization sequence needed by `MacBookPro16,1`.

References:

- [T2 Linux suspend workaround](https://wiki.t2linux.org/guides/postinstall/#suspend-workaround)
- [T2 Linux hardware support status](https://wiki.t2linux.org/state/)
- [Upstream suspend issue](https://github.com/t2linux/T2-Debian-and-Ubuntu-Kernel/issues/53)
- [Arch installation requirements](https://wiki.t2linux.org/distributions/arch/installation/)

## What the installer changes

1. Installs `suspend-fix-t2.service`, which:
   - stops `tiny-dfr`;
   - unloads `apple-bce` and Touch Bar modules before sleep;
   - restores the modules in the required order after wake;
   - restarts `tiny-dfr`.
2. Selects `deep` sleep through a systemd sleep drop-in.
3. adds the required `pm_async=off` kernel parameter.
4. Configures both physical fans. Omarchy's generated config may contain only
   `Fan1`, causing `t2fanrd` to crash continuously with `Missing Fan2 in config
   file` on this two-fan model.
5. Rebuilds the Limine unified kernel image.

Existing files are copied into a timestamped directory under
`/var/backups/t2-macbook-suspend-fix/` before modification.

## Install

```bash
git clone https://github.com/deens/t2-macbook-suspend-fix.git
cd t2-macbook-suspend-fix
sudo ./install.sh
sudo reboot
```

After reboot, verify the configuration:

```bash
./verify.sh
```

Then close the lid for at least 30 seconds and reopen it. Wake takes roughly
15 seconds because the T2 and Touch Bar devices are deliberately restored with
conservative delays.

## Uninstall or restore

The installer prints the backup directory it created. To remove the workaround:

```bash
sudo ./uninstall.sh
sudo reboot
```

To restore a particular backup as well:

```bash
sudo ./uninstall.sh /var/backups/t2-macbook-suspend-fix/YYYYMMDD-HHMMSS
sudo reboot
```

## Troubleshooting

Inspect the previous boot after a forced restart:

```bash
journalctl -b -1 | grep -Ei 'lid|suspend|resume|apple-bce|tiny-dfr|t2fan'
```

Confirm the boot parameter:

```bash
cat /proc/cmdline
```

Confirm both fans are recognized:

```bash
journalctl -u t2fanrd -b
```

If Wi-Fi fails after resume, consult the optional Wi-Fi module handling in the
[T2 Linux workaround](https://wiki.t2linux.org/guides/postinstall/#suspend-workaround).

## Safety notes

- Forced module unloading is required by the documented workaround and by the
  T2 kernel's `CONFIG_MODULE_FORCE_UNLOAD=y` option.
- Do not run the installer on a non-T2 Mac.
- The installer does not contain disk UUIDs, usernames, credentials, or other
  data copied from the original machine.

## License

MIT
