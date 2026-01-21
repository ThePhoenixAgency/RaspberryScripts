**docs/maintenance-rpi.en.md**

```markdown
# 🧰 Raspberry Pi Maintenance Menu (GUI + CLI) – EN

This script provides a full maintenance menu for Raspberry Pi:

- Automatic updates twice a day (`apt update && apt upgrade -y`)
- GUI menu (Zenity) and CLI menu (1–9)
- Root cron management (list, add, delete, replace)
- Viewing the update log (`/var/log/update-system.log`)

---

## Related scripts

- FR installer: `../scripts/install-maintenance-rpi.fr.sh`
- EN installer: `../scripts/install-maintenance-rpi.en.sh`

The installed system script is: `/usr/local/bin/update-system.sh`.

---

## Installation

1. Copy `../scripts/install-maintenance-rpi.en.sh` to the Raspberry Pi.
2. Make the script executable:

```bash
chmod +x install-maintenance-rpi.en.sh

    Run the installer script:

bash
./install-maintenance-rpi.en.sh

Usage
GUI / CLI menu

From the desktop:

    Double-click the "Maintenance (GUI+CLI)" icon

    or run:

bash
/usr/local/bin/update-system.sh

The script first tries the GUI, then falls back to the CLI if needed.
Main features

    System update

    Reboot / shutdown

    Show root crons

    Add / delete / replace root cron lines

    Show update log

Auto‑update cron

After installation, the root crontab contains:

text
# Automatic system update twice a day at 06:00 and 18:00
0 6,18 * * * /usr/local/bin/update-system.sh --auto

Show cron:

bash
sudo crontab -l

Show log:

bash
sudo tail -n 50 /var/log/update-system.log
