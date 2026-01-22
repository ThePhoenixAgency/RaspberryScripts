#!/bin/bash
set -e

###############################################################################
# GLOBAL CONFIG
###############################################################################
SCRIPT_PATH="/usr/local/bin/update-system.sh"
DESKTOP_PATH="$HOME/Desktop/Supervision.desktop"
LOG_FILE="/var/log/update-system.log"

# Forced NVMe: 2 existing partitions
NVME_PART1_DEV="/dev/nvme0n1p1"
NVME_PART2_DEV="/dev/nvme0n1p2"
NVME_PART1_MOUNT="/mnt/nvme1"
NVME_PART2_MOUNT="/mnt/nvme2"

# Retention periods
SAVE_RETENTION_DAYS=3     # backups: keep max 3
LOG_RETENTION_DAYS=7      # logs: keep max 7 days

###############################################################################
# NVMe FUNCTIONS: MOUNT IF PRESENT, SILENT IF NOT
###############################################################################
mount_nvme_partition() {
  local dev="$1"
  local mnt="$2"

  [ -z "$dev" ] && return 1
  [ -z "$mnt" ] && return 1

  # Block device does not exist -> do nothing (no hard error).
  if [ ! -b "$dev" ]; then
    return 0
  fi

  sudo mkdir -p "$mnt"

  # Already mounted -> do nothing.
  if findmnt -M "$mnt" >/dev/null 2>&1; then
    return 0
  fi

  # Try to mount, only log on success/failure.
  if sudo mount "$dev" "$mnt"; then
    echo "NVMe: $dev mounted on $mnt"
  else
    echo "NVMe: failed to mount $dev on $mnt"
  fi
}

prepare_nvme() {
  local any=0

  if [ -b "$NVME_PART1_DEV" ]; then
    any=1
    mount_nvme_partition "$NVME_PART1_DEV" "$NVME_PART1_MOUNT"
  fi

  if [ -b "$NVME_PART2_DEV" ]; then
    any=1
    mount_nvme_partition "$NVME_PART2_DEV" "$NVME_PART2_MOUNT"
  fi

  # If no NVMe device exists, stay silent.
  [ "$any" -eq 0 ] && return 0
}

# Always prepare NVMe BEFORE anything else.
prepare_nvme

###############################################################################
# INSTALL / UPDATE MAIN SCRIPT
###############################################################################
sudo tee "$SCRIPT_PATH" >/dev/null << 'EOF_SCRIPT'
#!/bin/bash

LOG_FILE="/var/log/update-system.log"
SAVE_RETENTION_DAYS=3
LOG_RETENTION_DAYS=7

###############################################################################
# BACKUP TARGET SELECTION
###############################################################################
# Logic:
# - If /mnt/nvme1 or /mnt/nvme2 is mounted, pick the one with more free space.
# - Otherwise, fallback to SD: backups under /save and /logs on rootfs.
choose_backup_root() {
  local candidates=()

  if mountpoint -q /mnt/nvme1; then
    candidates+=("/mnt/nvme1")
  fi
  if mountpoint -q /mnt/nvme2; then
    candidates+=("/mnt/nvme2")
  fi

  if [ "${#candidates[@]}" -eq 0 ]; then
    # No NVMe mounted: use rootfs (SD) for backup.
    echo "/"
    return 0
  fi

  # Pick the mountpoint with the largest free space (in bytes).
  local best=""
  local best_avail=-1
  local path
  for path in "${candidates[@]}"; do
    local avail
    avail=$(df -B1 "$path" | awk 'NR==2 {print $4}')
    if [ "$avail" -gt "$best_avail" ]; then
      best_avail="$avail"
      best="$path"
    fi
  done

  [ -z "$best" ] && echo "/" || echo "$best"
}

# Returns backup and logs directories for the current host.
get_paths() {
  local root
  root=$(choose_backup_root)
  local save_dir log_dir

  if [ "$root" = "/" ]; then
    # No NVMe: stay on SD card, isolate backups/logs in /save and /logs.
    save_dir="/save"
    log_dir="/logs"
  else
    save_dir="$root/save"
    log_dir="$root/logs"
  fi

  echo "$save_dir;$log_dir"
}

###############################################################################
# BACKUP: SYSTEM + ADMIN SCRIPTS (WITH INTEGRITY CHECK)
###############################################################################
run_backup() {
  local paths; paths=$(get_paths)
  local save_root log_root
  save_root=$(echo "$paths" | cut -d';' -f1)
  log_root=$(echo "$paths" | cut -d';' -f2)

  sudo mkdir -p "$save_root" "$log_root"
  sudo chmod 755 "$save_root" "$log_root"

  local date_tag
  date_tag=$(date +%Y-%m-%d_%H-%M-%S)

  local backup_dir="${save_root}/${date_tag}"
  sudo mkdir -p "$backup_dir"

  # Data to backup:
  # - /etc, /usr/local, /home, /root (includes admin scripts).
  local backup_tar="${backup_dir}/system-backup.tar.gz"
  local hash_file="${backup_dir}/system-backup.sha256"
  local size_file="${backup_dir}/system-backup.size"

  sudo tar -cpzf "$backup_tar" /etc /usr/local /home /root 2>/dev/null

  # Integrity meta SHA256 + size (bytes).
  (cd "$backup_dir" && sudo sha256sum "$(basename "$backup_tar")" > "$(basename "$hash_file")")
  (cd "$backup_dir" && sudo stat -c '%s' "$(basename "$backup_tar")" > "$(basename "$size_file")")

  # Backup rotation: keep only the last SAVE_RETENTION_DAYS entries (sorted by name).
  sudo find "$save_root" -maxdepth 1 -mindepth 1 -type d \
    -printf '%P\n' | sort | head -n -"${SAVE_RETENTION_DAYS}" 2>/dev/null | while read -r old; do
      [ -n "$old" ] && sudo rm -rf "$save_root/$old"
    done

  # Logs rotation: delete files older than LOG_RETENTION_DAYS in log_root.
  sudo find "$log_root" -type f -mtime +"$LOG_RETENTION_DAYS" -delete 2>/dev/null
}

###############################################################################
# BACKUP INTEGRITY CHECK (HASH + SIZE)
###############################################################################
check_backup_integrity() {
  local backup_dir="$1"
  local backup_tar="${backup_dir}/system-backup.tar.gz"
  local hash_file="${backup_dir}/system-backup.sha256"
  local size_file="${backup_dir}/system-backup.size"

  [ -f "$backup_tar" ] || return 1
  [ -f "$hash_file" ] || return 1
  [ -f "$size_file" ] || return 1

  local expected_hash expected_size
  expected_hash=$(cut -d' ' -f1 "$hash_file")
  expected_size=$(cat "$size_file")

  local current_hash current_size
  current_hash=$(sha256sum "$backup_tar" | awk '{print $1}')
  current_size=$(stat -c '%s' "$backup_tar")

  [ "$expected_hash" = "$current_hash" ] || return 1
  [ "$expected_size" = "$current_size" ] || return 1

  return 0
}

###############################################################################
# RESTORE: CHOOSE BACKUP BY DATE + INTEGRITY CHECK
###############################################################################
restore_backup() {
  local paths; paths=$(get_paths)
  local save_root
  save_root=$(echo "$paths" | cut -d';' -f1)

  [ -d "$save_root" ] || {
    echo "No backups directory found at $save_root."
    return 1
  }

  local backups
  backups=$(ls -1 "$save_root" | sort -r)
  [ -z "$backups" ] && {
    echo "No backups found."
    return 1
  }

  echo "Available backups (most recent first):"
  echo "$backups" | nl -w2 -s') '
  echo
  read -rp "Select backup number to restore: " num

  local chosen
  chosen=$(echo "$backups" | sed -n "${num}p")
  [ -z "$chosen" ] && {
    echo "Invalid choice."
    return 1
  }

  local backup_dir="${save_root}/${chosen}"
  echo "Checking backup integrity for: ${chosen}"
  if ! check_backup_integrity "$backup_dir"; then
    echo "Integrity check failed (hash or size mismatch). Restore aborted."
    return 1
  fi

  echo "Restoring from ${backup_dir}..."
  sudo tar -xpf "${backup_dir}/system-backup.tar.gz" -C /
  echo "Restore completed."
}

###############################################################################
# AUTO MODE (--auto): USED BY ROOT CRON (UPDATE ONLY)
###############################################################################
if [ "$1" = "--auto" ]; then
  export DEBIAN_FRONTEND=noninteractive
  {
    echo "===== $(date) ====="
    apt update && apt -y upgrade
    echo
  } >> "$LOG_FILE" 2>&1

  if [ -n "$DISPLAY" ] && command -v notify-send >/dev/null 2>&1; then
    notify-send "Raspberry Pi" "Automatic update completed (see $LOG_FILE)"
  fi
  exit 0
fi

# Special entry point for GUI-triggered restore in a terminal.
if [ "$1" = "--restore-cli" ]; then
  restore_backup
  exit 0
fi

###############################################################################
# ROOT CRON MANAGEMENT FUNCTIONS
###############################################################################
show_crons() {
  sudo crontab -l 2>/dev/null || echo "(No root cron defined)"
}

add_cron_line() {
  local newline="$1"
  [ -z "$newline" ] && return 1
  TMPFILE=$(mktemp)
  sudo crontab -l 2>/dev/null > "$TMPFILE" || true
  echo "$newline" >> "$TMPFILE"
  sudo crontab "$TMPFILE"
  rm -f "$TMPFILE"
}

delete_cron_line() {
  local pattern="$1"
  [ -z "$pattern" ] && return 1
  TMPFILE=$(mktemp)
  sudo crontab -l 2>/dev/null > "$TMPFILE" || true
  sed -i "\\|$pattern|d" "$TMPFILE"
  sudo crontab "$TMPFILE"
  rm -f "$TMPFILE"
}

replace_cron_line() {
  local pattern="$1"
  local newline="$2"
  [ -z "$pattern" ] && return 1
  [ -z "$newline" ] && return 1
  TMPFILE=$(mktemp)
  sudo crontab -l 2>/dev/null > "$TMPFILE" || true
  sed -i "\\|$pattern|d" "$TMPFILE"
  echo "$newline" >> "$TMPFILE"
  sudo crontab "$TMPFILE"
  rm -f "$TMPFILE"
}

###############################################################################
# CLI MENU (TEXT) WITH LOG/BACKUP/RESTORE
###############################################################################
cli_menu() {
  while true; do
    clear
    echo "===== Raspberry Pi Supervision (CLI) ====="
    echo "1) Update (apt update && apt upgrade -y)"
    echo "2) Reboot"
    echo "3) Power off"
    echo "4) Show root crons"
    echo "5) Add root cron line"
    echo "6) Delete root cron line"
    echo "7) Replace root cron line"
    echo "8) Show update log (latest on top)"
    echo "9) Run backup now"
    echo "10) Restore a backup"
    echo "11) Quit"
    echo "-----------------------------------------"
    read -rp "Choose an option (1-11): " CHOICE

    case "$CHOICE" in
      1)
        sudo apt update && sudo apt upgrade -y | tee -a "$LOG_FILE"
        echo; echo "Update finished. Press Enter to go back."
        read -r
        ;;
      2)
        read -rp "Confirm reboot? (y/N): " C
        [ "$C" = "y" ] || [ "$C" = "Y" ] && sudo reboot
        ;;
      3)
        read -rp "Confirm shutdown? (y/N): " C
        [ "$C" = "y" ] || [ "$C" = "Y" ] && sudo shutdown -h now
        ;;
      4)
        clear
        echo "===== Root crons ====="
        show_crons
        echo; echo "Press Enter to go back."
        read -r
        ;;
      5)
        echo "Example: 0 6,18 * * * /usr/local/bin/update-system.sh --auto"
        read -rp "Full cron line to add: " NEWCRON
        add_cron_line "$NEWCRON"
        echo; show_crons; echo; echo "Press Enter to go back."
        read -r
        ;;
      6)
        echo "Current root crons:"; show_crons; echo
        read -rp "Pattern to delete: " PAT
        delete_cron_line "$PAT"
        echo; show_crons; echo; echo "Press Enter to go back."
        read -r
        ;;
      7)
        echo "Current root crons:"; show_crons; echo
        read -rp "Pattern to replace: " PAT
        echo "New full cron line:"
        read -rp "> " NEWCRON
        replace_cron_line "$PAT" "$NEWCRON"
        echo; show_crons; echo; echo "Press Enter to go back."
        read -r
        ;;
      8)
        clear
        echo "===== Update log ($LOG_FILE) ====="
        sudo tac "$LOG_FILE" 2>/dev/null | head -n 200 || echo "(No log yet)"
        echo; echo "Press Enter to go back."
        read -r
        ;;
      9)
        run_backup
        echo; echo "Backup executed. Press Enter to go back."
        read -r
        ;;
      10)
        restore_backup
        echo; echo "Press Enter to go back."
        read -r
        ;;
      11)
        exit 0
        ;;
      *)
        echo "Invalid choice. Press Enter."
        read -r
        ;;
    esac
  done
}

###############################################################################
# GUI MENU (ZENITY) WITH LOG/BACKUP/RESTORE
###############################################################################
gui_menu() {
  if ! command -v zenity >/dev/null 2>&1; then
    sudo apt update && sudo apt install -y zenity || return 1
  fi

  while true; do
    ACTION=$(zenity --list \
      --title="Raspberry Pi Supervision" \
      --text="Choose an action:" \
      --column="Action" --column="Description" \
      "update" "Update (apt update && apt upgrade -y)" \
      "reboot" "Reboot Raspberry Pi" \
      "poweroff" "Shutdown Raspberry Pi" \
      "show_crons" "Show root crons" \
      "add_cron" "Add root cron line" \
      "del_cron" "Delete root cron line" \
      "edit_cron" "Replace root cron line" \
      "show_log" "Show update log" \
      "backup_now" "Run backup now" \
      "restore_backup" "Restore a backup" \
      "exit" "Quit" \
      --height=580 --width=950) || return 1

    case "$ACTION" in
      "update")
        gnome-terminal --geometry=100x35 -- bash -c 'echo "Updating..."; sudo apt update && sudo apt upgrade -y | tee -a /var/log/update-system.log; echo; echo "Done. Close this window."; read -n1'
        ;;
      "reboot")
        zenity --question --title="Reboot" --text="Really reboot?" && sudo reboot
        ;;
      "poweroff")
        zenity --question --title="Shutdown" --text="Really power off?" && sudo shutdown -h now
        ;;
      "show_crons")
        show_crons | zenity --text-info --title="Root crons" --width=950 --height=580
        ;;
      "add_cron")
        EXAMPLE="0 6,18 * * * /usr/local/bin/update-system.sh --auto"
        NEWCRON=$(zenity --entry --title="Add cron" --text="Full cron line (ex: $EXAMPLE):")
        [ -n "$NEWCRON" ] && add_cron_line "$NEWCRON"
        show_crons | zenity --text-info --title="Root crons (after add)" --width=950 --height=580
        ;;
      "del_cron")
        CURRENT=$(show_crons)
        PAT=$(zenity --entry --title="Delete cron" --text="Current crons:\n$CURRENT\n\nPattern to delete:")
        [ -n "$PAT" ] && delete_cron_line "$PAT"
        show_crons | zenity --text-info --title="Root crons (after delete)" --width=950 --height=580
        ;;
      "edit_cron")
        CURRENT=$(show_crons)
        PAT=$(zenity --entry --title="Replace cron" --text="Current crons:\n$CURRENT\n\nPattern to replace:")
        [ -n "$PAT" ] || continue
        NEWCRON=$(zenity --entry --title="New cron line" --text="New full cron line:")
        [ -n "$NEWCRON" ] && replace_cron_line "$PAT" "$NEWCRON"
        show_crons | zenity --text-info --title="Root crons (after replace)" --width=950 --height=580
        ;;
      "show_log")
        TMPLOG=$(mktemp)
        sudo tac "$LOG_FILE" 2>/dev/null | head -n 400 > "$TMPLOG" || echo "(No log yet)" > "$TMPLOG"
        zenity --text-info --title="Update log" --width=950 --height=580 --filename="$TMPLOG"
        rm -f "$TMPLOG"
        ;;
      "backup_now")
        run_backup
        zenity --info --title="Backup" --text="Backup executed with automatic rotation."
        ;;
      "restore_backup")
        gnome-terminal --geometry=100x30 -- bash -c '/usr/local/bin/update-system.sh --restore-cli; echo; echo "Done. Close this window."; read -n1'
        ;;
      "exit"|"")
        return 0
        ;;
    esac
  done
}

###############################################################################
# AUTO-SELECTION: GUI IF POSSIBLE, OTHERWISE CLI
###############################################################################
if [ -n "$DISPLAY" ]; then
  gui_menu || cli_menu
else
  cli_menu
fi
EOF_SCRIPT

###############################################################################
# ROOT CRON DEFAULT: AUTO-UPDATE + TEMP CLEANUP
###############################################################################
sudo bash -c "cat > /tmp/root_cron_supervision << 'EOF_SCRIPT'
# Automatic update twice a day (06:00 and 18:00)
0 6,18 * * * /usr/local/bin/update-system.sh --auto

# Temp and cache cleanup every day at 04:00
0 4 * * * find /tmp -type f -atime +7 -delete && find /var/tmp -type f -atime +7 -delete
EOF_SCRIPT"

sudo crontab /tmp/root_cron_supervision
rm -f /tmp/root_cron_supervision

###############################################################################
# DESKTOP SHORTCUT: LXTERMINAL WITH HIGHER WINDOW
###############################################################################
mkdir -p "$HOME/Desktop"
rm -f "$DESKTOP_PATH"

cat > "$DESKTOP_PATH" << EOF_DESKTOP
[Desktop Entry]
Type=Application
Name=Supervision
Comment=Update / reboot / shutdown / cron / backup
Exec=lxterminal --geometry=100x35 -e /usr/local/bin/update-system.sh
Icon=system-software-update
Terminal=false
EOF_DESKTOP

chmod +x "$SCRIPT_PATH"
chmod +x "$DESKTOP_PATH"
