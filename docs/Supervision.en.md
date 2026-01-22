# 🧰 Raspberry Pi Supervision Menu (GUI + CLI) – EN

This script provides a full **supervision** menu for Raspberry Pi:

- Automatic system updates via cron (`apt update && apt upgrade -y`)
- Automatic cleanup of temporary files (`/tmp`, `/var/tmp`)
- Graphical menu (Zenity) and CLI menu (multiple options)
- Root cron management (list, add, delete, replace)
- Viewing update logs (most recent entries first)
- Automatic system + admin scripts backups
  - Detects the best disk (NVMe or SD card)
  - Backup rotation (keeps 3 backups)
  - Integrity check (SHA256 hash + size)
  - Restore by date (Windows “restore point” style)
- Centralized logs with 7‑day retention

The main system script installed is: `/usr/local/bin/update-system.sh`.

---

## Related scripts

- FR installer: [`../scripts/install-supervision.fr.sh`](../scripts/install-supervision-rpi.fr.sh)  
- EN installer: [`../scripts/install-supervision.en.sh`](../scripts/install-supervision-rpi.en.sh)

---

## Installation

1. Copy `../scripts/install-supervision.en.sh` to your Raspberry Pi.
2. Make the installer executable:

   ```bash
   chmod +x install-supervision.en.sh
