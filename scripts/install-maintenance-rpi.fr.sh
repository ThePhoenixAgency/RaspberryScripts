#!/bin/bash
set -e

SCRIPT_PATH="/usr/local/bin/update-system.sh"
DESKTOP_PATH="$HOME/Desktop/Maintenance-RPi.desktop"
LOG_FILE="/var/log/update-system.log"

sudo tee "$SCRIPT_PATH" >/dev/null << 'EOF_SCRIPT'
#!/bin/bash

CRON_LINE='0 6,18 * * * /usr/local/bin/update-system.sh --auto'
LOG_FILE="/var/log/update-system.log"

if [ "$1" = "--auto" ]; then
  export DEBIAN_FRONTEND=noninteractive
  {
    echo "===== $(date) ====="
    apt update && apt -y upgrade
    echo
  } >> "$LOG_FILE" 2>&1
  if [ -n "$DISPLAY" ] && command -v notify-send >/dev/null 2>&1; then
    notify-send "Raspberry Pi" "Mise à jour auto terminée (voir $LOG_FILE)"
  fi
  exit 0
fi

show_crons() {
  sudo crontab -l 2>/dev/null || echo "(Aucun cron root défini)"
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
    echo "===== Maintenance Raspberry Pi (CLI) ====="
    echo "1) Mise à jour (apt update && apt upgrade -y)"
    echo "2) Redémarrer"
    echo "3) Éteindre"
    echo "4) Voir les crons root"
    echo "5) Ajouter une ligne cron root"
    echo "6) Supprimer une ligne cron root"
    echo "7) Remplacer une ligne cron root"
    echo "8) Voir le log des mises à jour"
    echo "9) Quitter"
    echo "-----------------------------------------"
    read -rp "Choisis un numéro (1-9) : " CHOICE

    case "$CHOICE" in
      1)
        sudo apt update && sudo apt upgrade -y | tee -a "$LOG_FILE"
        echo
        echo "Mise à jour terminée. Entrée pour revenir au menu."
        read -r
        ;;
      2)
        read -rp "Confirmer le redémarrage ? (o/N) : " C
        [ "$C" = "o" ] || [ "$C" = "O" ] && sudo reboot
        ;;
      3)
        read -rp "Confirmer l'arrêt ? (o/N) : " C
        [ "$C" = "o" ] || [ "$C" = "O" ] && sudo shutdown -h now
        ;;
      4)
        clear
        echo "===== Crons root ====="
        show_crons
        echo
        echo "Entrée pour revenir au menu."
        read -r
        ;;
      5)
        echo "Exemple de syntaxe :"
        echo "0 6,18 * * * /usr/local/bin/update-system.sh --auto"
        read -rp "Tape la ligne cron complète à ajouter : " NEWCRON
        add_cron_line "$NEWCRON"
        echo
        echo "Crons root après ajout :"
        show_crons
        echo
        echo "Entrée pour revenir au menu."
        read -r
        ;;
      6)
        echo "Crons root actuels :"
        show_crons
        echo
        read -rp "Tape un bout de la ligne à supprimer (pattern) : " PAT
        delete_cron_line "$PAT"
        echo
        echo "Crons root après suppression éventuelle :"
        show_crons
        echo
        echo "Entrée pour revenir au menu."
        read -r
        ;;
      7)
        echo "Crons root actuels :"
        show_crons
        echo
        read -rp "Tape un bout de la ligne à remplacer (pattern) : " PAT
        echo "Nouvelle ligne cron complète :"
        read -rp "> " NEWCRON
        replace_cron_line "$PAT" "$NEWCRON"
        echo
        echo "Crons root après remplacement :"
        show_crons
        echo
        echo "Entrée pour revenir au menu."
        read -r
        ;;
      8)
        clear
        echo "===== Log des mises à jour ($LOG_FILE) ====="
        sudo tail -n 50 "$LOG_FILE" 2>/dev/null || echo "(Pas encore de log)"
        echo
        echo "Entrée pour revenir au menu."
        read -r
        ;;
      9)
        exit 0
        ;;
      *)
        echo "Choix invalide. Entrée pour réessayer."
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
      --title="Maintenance Raspberry Pi" \
      --text="Choisis une action :" \
      --column="Action" --column="Description" \
      "update"       "Mettre à jour (apt update && apt upgrade -y)" \
      "reboot"       "Redémarrer le Raspberry Pi" \
      "poweroff"     "Éteindre le Raspberry Pi" \
      "show_crons"   "Afficher les crons root" \
      "add_cron"     "Ajouter une ligne cron root" \
      "del_cron"     "Supprimer une ligne cron root" \
      "edit_cron"    "Remplacer une ligne cron root" \
      "show_log"     "Voir le log des mises à jour" \
      "exit"         "Quitter le menu" \
      --height=480 --width=820) || return 1

    case "$ACTION" in
      "update")
        gnome-terminal -- bash -c 'echo "Mise à jour..."; sudo apt update && sudo apt upgrade -y | tee -a /var/log/update-system.log; echo; echo "Terminé. Fermer cette fenêtre."; read -n1'
        ;;
      "reboot")
        zenity --question --title="Redémarrer" --text="Tu veux vraiment redémarrer ?" && sudo reboot
        ;;
      "poweroff")
        zenity --question --title="Éteindre" --text="Tu veux vraiment éteindre le Raspberry Pi ?" && sudo shutdown -h now
        ;;
      "show_crons")
        show_crons | zenity --text-info --title="Crons root" --width=820 --height=520
        ;;
      "add_cron")
        EXAMPLE="0 6,18 * * * /usr/local/bin/update-system.sh --auto"
        NEWCRON=$(zenity --entry --title="Ajouter un cron" --text="Ligne cron complète (ex : $EXAMPLE) :")
        [ -n "$NEWCRON" ] && add_cron_line "$NEWCRON"
        show_crons | zenity --text-info --title="Crons root (après ajout)" --width=820 --height=520
        ;;
      "del_cron")
        CURRENT=$(show_crons)
        PAT=$(zenity --entry --title="Supprimer un cron" --text="Crons actuels :\n$CURRENT\n\nTape un bout de la ligne à supprimer (pattern) :")
        [ -n "$PAT" ] && delete_cron_line "$PAT"
        show_crons | zenity --text-info --title="Crons root (après suppression)" --width=820 --height=520
        ;;
      "edit_cron")
        CURRENT=$(show_crons)
        PAT=$(zenity --entry --title="Remplacer un cron" --text="Crons actuels :\n$CURRENT\n\nTape un bout de la ligne à remplacer (pattern) :")
        [ -n "$PAT" ] || continue
        NEWCRON=$(zenity --entry --title="Nouvelle ligne cron" --text="Nouvelle ligne cron complète :")
        [ -n "$NEWCRON" ] && replace_cron_line "$PAT" "$NEWCRON"
        show_crons | zenity --text-info --title="Crons root (après remplacement)" --width=820 --height=520
        ;;
      "show_log")
        sudo tail -n 80 "$LOG_FILE" 2>/dev/null | zenity --text-info --title="Log des mises à jour" --width=820 --height=520
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
# Mise à jour automatique 2x/jour à 06h et 18h
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
Comment=Update / reboot / arrêt / cron
Exec=lxterminal -e /usr/local/bin/update-system.sh
Icon=system-software-update
Terminal=false
EOF_DESKTOP

chmod +x "$SCRIPT_PATH"
chmod +x "$DESKTOP_PATH"
