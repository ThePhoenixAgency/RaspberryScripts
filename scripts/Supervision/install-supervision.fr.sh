#!/bin/bash
set -e

###############################################################################
# CONFIG GLOBALE
###############################################################################
SCRIPT_PATH="/usr/local/bin/update-system.sh"
DESKTOP_PATH="$HOME/Desktop/Supervision.desktop"
LOG_FILE="/var/log/update-system.log"

# NVMe forcé : 2 partitions existantes
NVME_PART1_DEV="/dev/nvme0n1p1"
NVME_PART2_DEV="/dev/nvme0n1p2"
NVME_PART1_MOUNT="/mnt/nvme1"
NVME_PART2_MOUNT="/mnt/nvme2"

# Durées de rétention
SAVE_RETENTION_DAYS=3     # sauvegardes : 3 jours max
LOG_RETENTION_DAYS=7      # logs : 7 jours max

###############################################################################
# FONCTIONS NVMe : MONTAGE SI PRÉSENT, SILENCE SI INEXISTANT
###############################################################################
mount_nvme_partition() {
  local dev="$1"
  local mnt="$2"

  [ -z "$dev" ] && return 1
  [ -z "$mnt" ] && return 1

  # Device inexistant -> on ne fait rien. [web:72]
  if [ ! -b "$dev" ]; then
    return 0
  fi

  sudo mkdir -p "$mnt"

  if findmnt -M "$mnt" >/dev/null 2>&1; then
    return 0
  fi

  if sudo mount "$dev" "$mnt"; then
    echo "NVMe : $dev monté sur $mnt"
  else
    echo "NVMe : échec du montage de $dev sur $mnt"
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

  # Si aucun NVMe, pas de bruit.
  [ "$any" -eq 0 ] && return 0
}

# Toujours avant tout le reste. [web:72][web:84]
prepare_nvme

###############################################################################
# INSTALLATION / MISE À JOUR DU SCRIPT PRINCIPAL
###############################################################################
sudo tee "$SCRIPT_PATH" >/dev/null << 'EOF_SCRIPT'
#!/bin/bash

LOG_FILE="/var/log/update-system.log"
SAVE_RETENTION_DAYS=3
LOG_RETENTION_DAYS=7

# Choix du disque de sauvegarde :
# - si /mnt/nvme1 ou /mnt/nvme2 existe et est monté, on prend celui qui a le plus de place.
# - sinon, on reste sur la SD (sauvegardes locales sur /save et /logs). [web:88][web:89]
choose_backup_root() {
  local candidates=()

  if mountpoint -q /mnt/nvme1; then
    candidates+=("/mnt/nvme1")
  fi
  if mountpoint -q /mnt/nvme2; then
    candidates+=("/mnt/nvme2")
  fi

  if [ "${#candidates[@]}" -eq 0 ]; then
    # Pas de NVMe monté : sauvegarde locale sur SD.
    echo "/"
    return 0
  fi

  # On choisit le point de montage avec le plus d'espace disponible. [web:88][web:89]
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

# Retourne les dossiers de backup et de logs à utiliser.
get_paths() {
  local root
  root=$(choose_backup_root)
  local save_dir log_dir

  if [ "$root" = "/" ]; then
    # Pas de NVMe : on reste sur SD (mais on isole dans /save et /logs).
    save_dir="/save"
    log_dir="/logs"
  else
    save_dir="$root/save"
    log_dir="$root/logs"
  fi

  echo "$save_dir;$log_dir"
}

# Sauvegarde du système + scripts des admins, avec intégrité (hash + taille). [web:92][web:95][web:98]
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

  # Dossiers à sauvegarder :
  # - /etc, /usr/local, /home, /root (scripts admin inclus). [web:88]
  # On archive en tar.gz avec hash SHA256 + taille pour vérif ultérieure. [web:92][web:95][web:98]
  local backup_tar="${backup_dir}/system-backup.tar.gz"
  local hash_file="${backup_dir}/system-backup.sha256"
  local size_file="${backup_dir}/system-backup.size"

  sudo tar -cpzf "$backup_tar" /etc /usr/local /home /root 2>/dev/null

  # Calcul de hash et taille. [web:92][web:95]
  (cd "$backup_dir" && sudo sha256sum "$(basename "$backup_tar")" > "$(basename "$hash_file")")
  (cd "$backup_dir" && sudo stat -c '%s' "$(basename "$backup_tar")" > "$(basename "$size_file")")

  # Rotation des sauvegardes : ne garder que les 3 plus récentes. [web:88]
  sudo find "$save_root" -maxdepth 1 -mindepth 1 -type d \
    -printf '%P\n' | sort | head -n -"${SAVE_RETENTION_DAYS}" 2>/dev/null | while read -r old; do
      [ -n "$old" ] && sudo rm -rf "$save_root/$old"
    done

  # Rotation des logs dans le répertoire de logs (7 jours). [web:88]
  sudo find "$log_root" -type f -mtime +"$LOG_RETENTION_DAYS" -delete 2>/dev/null
}

# Vérification d'intégrité d'une sauvegarde :
# - compare le hash SHA256 et la taille actuelle au metadata stocké. [web:92][web:95][web:98]
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

# Restauration d'une sauvegarde choisie :
# - propose la liste des dates,
# - vérifie intégrité, puis tar xpf dans / (avec sudo). [web:92][web:95]
restore_backup() {
  local paths; paths=$(get_paths)
  local save_root
  save_root=$(echo "$paths" | cut -d';' -f1)

  [ -d "$save_root" ] || {
    echo "Aucune sauvegarde disponible dans $save_root."
    return 1
  }

  # Liste des sauvegardes disponibles
  local backups
  backups=$(ls -1 "$save_root" | sort -r)
  [ -z "$backups" ] && {
    echo "Aucune sauvegarde trouvée."
    return 1
  }

  echo "Sauvegardes disponibles :"
  echo "$backups" | nl -w2 -s') '
  echo
  read -rp "Choisir le numéro de la sauvegarde à restaurer : " num

  local chosen
  chosen=$(echo "$backups" | sed -n "${num}p")
  [ -z "$chosen" ] && {
    echo "Choix invalide."
    return 1
  }

  local backup_dir="${save_root}/${chosen}"
  echo "Vérification de l'intégrité de la sauvegarde : ${chosen}"
  if ! check_backup_integrity "$backup_dir"; then
    echo "Intégrité invalide (hash ou taille incorrecte). Restauration annulée."
    return 1
  fi

  echo "Restauration en cours depuis ${backup_dir}..."
  sudo tar -xpf "${backup_dir}/system-backup.tar.gz" -C /
  echo "Restauration terminée."
}

###############################################################################
# MODE AUTO (--auto) : utilisé par le cron root (update uniquement)
###############################################################################
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

###############################################################################
# FONCTIONS GESTION CRON ROOT
###############################################################################
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
# MENU CLI (TEXTE) AVEC LOGS + BACKUP/RESTORE
###############################################################################
cli_menu() {
  while true; do
    clear
    echo "===== Supervision Raspberry Pi (CLI) ====="
    echo "1) Mettre à jour (apt update && apt upgrade -y)"
    echo "2) Redémarrer"
    echo "3) Éteindre"
    echo "4) Afficher les crons root"
    echo "5) Ajouter une ligne cron root"
    echo "6) Supprimer une ligne cron root"
    echo "7) Remplacer une ligne cron root"
    echo "8) Afficher le log des mises à jour"
    echo "9) Lancer une sauvegarde maintenant"
    echo "10) Restaurer une sauvegarde"
    echo "11) Quitter"
    echo "-----------------------------------------"
    read -rp "Choisir un numéro (1-11) : " CHOICE

    case "$CHOICE" in
      1)
        sudo apt update && sudo apt upgrade -y | tee -a "$LOG_FILE"
        echo; echo "Mise à jour terminée. Entrée pour revenir."
        read -r
        ;;
      2)
        read -rp "Confirmer le redémarrage ? (o/N) : " C
        [ "$C" = "o" ] || [ "$C" = "O" ] && sudo reboot
        ;;
      3)
        read -rp "Confirmer l'extinction ? (o/N) : " C
        [ "$C" = "o" ] || [ "$C" = "O" ] && sudo shutdown -h now
        ;;
      4)
        clear
        echo "===== Crons root ====="
        show_crons
        echo; echo "Entrée pour revenir."
        read -r
        ;;
      5)
        echo "Exemple : 0 6,18 * * * /usr/local/bin/update-system.sh --auto"
        read -rp "Ligne cron complète à ajouter : " NEWCRON
        add_cron_line "$NEWCRON"
        echo; show_crons; echo; echo "Entrée pour revenir."
        read -r
        ;;
      6)
        echo "Crons actuels :"; show_crons; echo
        read -rp "Motif à supprimer : " PAT
        delete_cron_line "$PAT"
        echo; show_crons; echo; echo "Entrée pour revenir."
        read -r
        ;;
      7)
        echo "Crons actuels :"; show_crons; echo
        read -rp "Motif à remplacer : " PAT
        echo "Nouvelle ligne cron complète :"
        read -rp "> " NEWCRON
        replace_cron_line "$PAT" "$NEWCRON"
        echo; show_crons; echo; echo "Entrée pour revenir."
        read -r
        ;;
      8)
        clear
        echo "===== Log des mises à jour ($LOG_FILE) ====="
        # Les plus récentes en haut : tac. [web:88]
        sudo tac "$LOG_FILE" 2>/dev/null | head -n 200 || echo "(Pas encore de log)"
        echo; echo "Entrée pour revenir."
        read -r
        ;;
      9)
        run_backup
        echo; echo "Sauvegarde exécutée. Entrée pour revenir."
        read -r
        ;;
      10)
        restore_backup
        echo; echo "Entrée pour revenir."
        read -r
        ;;
      11)
        exit 0
        ;;
      *)
        echo "Choix invalide. Entrée."
        read -r
        ;;
    esac
  done
}

###############################################################################
# MENU GUI (ZENITY) AVEC LOGS + BACKUP/RESTORE
###############################################################################
gui_menu() {
  if ! command -v zenity >/dev/null 2>&1; then
    sudo apt update && sudo apt install -y zenity || return 1
  fi

  while true; do
    ACTION=$(zenity --list \
      --title="Supervision Raspberry Pi" \
      --text="Choisir une action :" \
      --column="Action" --column="Description" \
      "update" "Mettre à jour (apt update && apt upgrade -y)" \
      "reboot" "Redémarrer le Raspberry Pi" \
      "poweroff" "Éteindre le Raspberry Pi" \
      "show_crons" "Afficher les crons root" \
      "add_cron" "Ajouter une ligne cron root" \
      "del_cron" "Supprimer une ligne cron root" \
      "edit_cron" "Remplacer une ligne cron root" \
      "show_log" "Afficher le log des mises à jour" \
      "backup_now" "Lancer une sauvegarde maintenant" \
      "restore_backup" "Restaurer une sauvegarde" \
      "exit" "Quitter" \
      --height=580 --width=950) || return 1

    case "$ACTION" in
      "update")
        gnome-terminal --geometry=100x35 -- bash -c 'echo "Mise à jour..."; sudo apt update && sudo apt upgrade -y | tee -a /var/log/update-system.log; echo; echo "Terminé. Fermer cette fenêtre."; read -n1'
        ;;
      "reboot")
        zenity --question --title="Redémarrage" --text="Vraiment redémarrer ?" && sudo reboot
        ;;
      "poweroff")
        zenity --question --title="Extinction" --text="Vraiment éteindre ?" && sudo shutdown -h now
        ;;
      "show_crons")
        show_crons | zenity --text-info --title="Crons root" --width=950 --height=580
        ;;
      "add_cron")
        EXAMPLE="0 6,18 * * * /usr/local/bin/update-system.sh --auto"
        NEWCRON=$(zenity --entry --title="Ajouter cron" --text="Ligne cron complète (ex: $EXAMPLE) :")
        [ -n "$NEWCRON" ] && add_cron_line "$NEWCRON"
        show_crons | zenity --text-info --title="Crons root (après ajout)" --width=950 --height=580
        ;;
      "del_cron")
        CURRENT=$(show_crons)
        PAT=$(zenity --entry --title="Supprimer cron" --text="Crons actuels :\n$CURRENT\n\nMotif à supprimer :")
        [ -n "$PAT" ] && delete_cron_line "$PAT"
        show_crons | zenity --text-info --title="Crons root (après suppression)" --width=950 --height=580
        ;;
      "edit_cron")
        CURRENT=$(show_crons)
        PAT=$(zenity --entry --title="Remplacer cron" --text="Crons actuels :\n$CURRENT\n\nMotif à remplacer :")
        [ -n "$PAT" ] || continue
        NEWCRON=$(zenity --entry --title="Nouvelle ligne cron" --text="Nouvelle ligne cron complète :")
        [ -n "$NEWCRON" ] && replace_cron_line "$PAT" "$NEWCRON"
        show_crons | zenity --text-info --title="Crons root (après remplacement)" --width=950 --height=580
        ;;
      "show_log")
        # On affiche le log dans un fichier temporaire, plus récent en haut. [web:90][web:93]
        TMPLOG=$(mktemp)
        sudo tac "$LOG_FILE" 2>/dev/null | head -n 400 > "$TMPLOG" || echo "(Pas encore de log)" > "$TMPLOG"
        zenity --text-info --title="Log des mises à jour" --width=950 --height=580 --filename="$TMPLOG"
        rm -f "$TMPLOG"
        ;;
      "backup_now")
        run_backup
        zenity --info --title="Sauvegarde" --text="Sauvegarde exécutée avec rotation automatique."
        ;;
      "restore_backup")
        # Restauration via CLI (prompts texte), mais déclenchée depuis GUI.
        gnome-terminal --geometry=100x30 -- bash -c '/usr/local/bin/update-system.sh --restore-cli; echo; echo "Terminé. Fermer cette fenêtre."; read -n1'
        ;;
      "exit"|"")
        return 0
        ;;
    esac
  done
}

# Entrée spéciale pour restauration depuis GUI
if [ "$1" = "--restore-cli" ]; then
  restore_backup
  exit 0
fi

###############################################################################
# CHOIX AUTO : GUI SI POSSIBLE, SINON CLI
###############################################################################
if [ -n "$DISPLAY" ]; then
  gui_menu || cli_menu
else
  cli_menu
fi
EOF_SCRIPT

###############################################################################
# CRON ROOT PAR DÉFAUT : AUTO-MAJ + NETTOYAGE TEMPORAIRES
###############################################################################
sudo bash -c "cat > /tmp/root_cron_supervision << 'EOF_SCRIPT'
# Mise à jour automatique 2x/jour (06h et 18h)
0 6,18 * * * /usr/local/bin/update-system.sh --auto

# Nettoyage des fichiers temporaires et cache tous les jours à 4h
0 4 * * * find /tmp -type f -atime +7 -delete && find /var/tmp -type f -atime +7 -delete
EOF_SCRIPT"

sudo crontab /tmp/root_cron_supervision
rm -f /tmp/root_cron_supervision

###############################################################################
# RACCOURCI BUREAU : LXTERMINAL AVEC FENÊTRE HAUTE
###############################################################################
mkdir -p "$HOME/Desktop"
rm -f "$DESKTOP_PATH"

cat > "$DESKTOP_PATH" << EOF_DESKTOP
[Desktop Entry]
Type=Application
Name=Supervision
Comment=Mise à jour / redémarrage / extinction / cron / backup
Exec=lxterminal --geometry=100x35 -e /usr/local/bin/update-system.sh
Icon=system-software-update
Terminal=false
EOF_DESKTOP

chmod +x "$SCRIPT_PATH"
chmod +x "$DESKTOP_PATH"
