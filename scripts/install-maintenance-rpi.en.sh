#!/bin/bash
set -e

SCRIPT_PATH="/usr/local/bin/update-system.sh"
DESKTOP_PATH="$HOME/Desktop/Maintenance-RPi.desktop"
LOG_FILE="/var/log/rpi-auto-update.log"

sudo tee "$SCRIPT_PATH" >/dev/null << 'EOF_SCRIPT'
#!/bin/bash

CRON_TAG="# Auto update twice a day (06:00 and 18:00) - do not edit outside Maintenance menu"
CRON_LINE='0 6,18 * * * /usr/local/bin/update-system.sh --auto'

LOG_FILE="/var/log/rpi-auto-update.log"

if [ "$1" = "--auto" ]; then
  export DEBIAN_FRONTEND=noninteractive
  {
    echo "===== $(date) ====="
    apt update && apt -y upgrade
    echo
  } >> "$LOG_FILE" 2>&1
  if [ -n "$DISPLAY" ] && command -v notify-send >/dev/null 2>&1; then
    notify-send "Raspberry Pi" "Auto update finished (see $LOG_FILE)"
  fi
  exit 0
fi

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
  sed -i "\|$pattern|d" "$TMPFILE"
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
  sed -i "\|$pattern|d" "$TMPFILE"
  echo "$newline" >> "$TMPFILE"
  sudo crontab "$TMPFILE"
  rm -f "$TMPFILE"
}

cli_menu() {
  while true; do
    clear
    echo "===== Raspberry Pi Maintenance (CLI) ====="
    echo "1) Update (apt update && apt upgrade -y)"
    echo "2) Reboot"
    echo "3) Shutdown"
    echo "4) Show root crons"
    echo "5) Add root cron line"
    echo "6) Delete root cron line"
    echo "7) Replace root cron line"
    echo "8) Show update log"
    echo "9) Quit"
    echo "-----------------------------------------"
    read -rp "Choose a number (1-9): " CHOICE

    case "$CHOICE" in
      1)
        sudo apt update && sudo apt upgrade -y | tee -a "$LOG_FILE"
        echo
        echo "Update finished. Press Enter to go back to menu."
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
        echo
        echo "Press Enter to go back to menu."
        read -r
        ;;
      5)
        echo "Example syntax:"
        echo "0 6,18 * * * /usr/local/bin/update-system.sh --auto"
        read -rp "Type the full cron line to add: " NEWCRON
        add_cron_line "$NEWCRON"
        echo
        echo "Root crons after add:"
        show_crons
        echo
        echo "Press Enter to go back to menu."
        read -r
        ;;
      6)
        echo "Current root crons:"
        show_crons
        echo
        read -rp "Type part of the line to delete (pattern): " PAT
        delete_cron_line "$PAT"
        echo
        echo "Root crons after delete attempt:"
        show_crons
        echo
        echo "Press Enter to go back to menu."
        read -r
        ;;
      7)
        echo "Current root crons:"
        show_crons
        echo
        read -rp "Type part of the line to replace (pattern): " PAT
        echo "New full cron line:"
        read -rp "> " NEWCRON
        replace_cron_line "$PAT" "$NEWCRON"
        echo
        echo "Root crons after replace:"
        show_crons
        echo
        echo "Press Enter to go back to menu."
        read -r
        ;;
      8)
        clear
        echo "===== Update log ($LOG_FILE) ====="
        sudo tail -n 50 "$LOG_FILE" 2>/dev/null || echo "(No log yet)"
        echo
        echo "Press Enter to go back to menu."
        read -r
        ;;
      9)
        exit 0
        ;;
      *)
        echo "Invalid choice. Press Enter to retry."
        read -r
        ;;
    esac
  done
}

gui_menu() {
  if ! command -v zenity >/dev/null 2>&1; then
    sudo apt update && sudo apt install -y zenity || return 1
  fi

  while true; do
    ACTION=$(zenity --list \
      --title="Raspberry Pi Maintenance" \
      --text="Choose an action:" \
      --column="Action" --column="Description" \
      "update"       "Update (apt update && apt upgrade -y)" \
      "reboot"       "Reboot Raspberry Pi" \
      "poweroff"     "Shutdown Raspberry Pi" \
      "show_crons"   "Show root crons" \
      "add_cron"     "Add root cron line" \
      "del_cron"     "Delete root cron line" \
      "edit_cron"    "Replace root cron line" \
      "show_log"     "Show update log" \
      "exit"         "Quit menu" \
      --height=480 --width=820) || return 1

    case "$ACTION" in
      "update")
        gnome-terminal -- bash -c 'echo "Updating..."; sudo apt update && sudo apt upgrade -y | tee -a /var/log/rpi-auto-update.log; echo; echo "Done. Close this window."; read -n1'
        ;;
      "reboot")
        zenity --question --title="Reboot" --text="Really reboot?" && sudo reboot
        ;;
      "poweroff")
        zenity --question --title="Shutdown" --text="Really shutdown?" && sudo shutdown -h now
        ;;
      "show_crons")
        show_crons | zenity --text-info --title="Root crons" --width=820 --height=520
        ;;
      "add_cron")
        EXAMPLE="0 6,18 * * * /usr/local/bin/update-system.sh --auto"
        NEWCRON=$(zenity --entry --title="Add cron" --text="Full cron line (ex: $EXAMPLE):")
        [ -n "$NEWCRON" ] && add_cron_line "$NEWCRON"
        show_crons | zenity --text-info --title="Root crons (after add)" --width=820 --height=520
        ;;
      "del_cron")
        CURRENT=$(show_crons)
        PAT=$(zenity --entry --title="Delete cron" --text="Current crons:\n$CURRENT\n\nType part of the line to delete (pattern):")
        [ -n "$PAT" ] && delete_cron_line "$PAT"
        show_crons | zenity --text-info --title="Root crons (after delete)" --width=820 --height=520
        ;;
      "edit_cron")
        CURRENT=$(show_crons)
        PAT=$(zenity --entry --title="Replace cron" --text="Current crons:\n$CURRENT\n\nType part of the line to replace (pattern):")
        [ -n "$PAT" ] || continue
        NEWCRON=$(zenity --entry --title="New cron line" --text="New full cron line:")
        [ -n "$NEWCRON" ] && replace_cron_line "$PAT" "$NEWCRON"
        show_crons | zenity --text-info --title="Root crons (after replace)" --width=820 --height=520
        ;;
      "show_log")
        sudo tail -n 80 "$LOG_FILE" 2>/dev/null | zenity --text-info --title="Update log" --width=820 --height=520
        ;;
      "exit"|"")
        return 0
        ;;
    esac
  done
}

if [ -n "$DISPLAY" ]; then
  gui_menu || cli_menu
else
  cli_menu
fi
EOF_SCRIPT

sudo bash -c "cat > /tmp/root_cron_maintenance << 'EOF_CRON'
# Auto update twice a day (06:00 and 18:00) - do not edit outside Maintenance menu
0 6,18 * * * /usr/local/bin/update-system.sh --auto
EOF_CRON"

sudo crontab /tmp/root_cron_maintenance
rm -f /tmp/root_cron_maintenance

mkdir -p "$HOME/Desktop"
rm -f "$DESKTOP_PATH"

cat > "$DESKTOP_PATH" << EOF_DESKTOP
[Desktop Entry]
Type=Application
Name=Maintenance (GUI+CLI)
Comment=Update / reboot / shutdown / cron
Exec=lxterminal -e /usr/local/bin/update-system.sh
Icon=system-software-update
Terminal=false
EOF_DESKTOP

chmod +x "$SCRIPT_PATH"
chmod +x "$DESKTOP_PATH"
