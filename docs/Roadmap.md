```markdown
# BACKLOG - Raspberry Pi Scripts Hub

Ce backlog décrit l'évolution prévue du hub de scripts et de l'installateur post-OS (Raspberry Pi / Debian), avec des idées concrètes et des exemples de commandes / structures à implémenter.

---

## MODULES DE SUPERVISION (POST-OS)

Objectif : transformer l'installateur en assistant post-OS qui propose plusieurs modules à cocher, puis configure automatiquement scripts + crons en fonction des besoins.

Tâches :

- Ajouter un menu de sélection de modules dans `install-supervision-rpi.fr.sh` / `install-supervision-rpi.en.sh` :
  - En GUI : checklist Zenity.
  - En CLI : sélection multiple (ex: 1 2 3).

Exemple d'UI Zenity (FR) :

```bash
CHOICES=$(zenity --list \
  --title="Raspberry Pi - Modules à installer" \
  --text="Choisir les modules à installer :" \
  --checklist \
  --column="Choisir" --column="ID" --column="Description" \
  TRUE  "base"      "Supervision de base (menu + auto update + nettoyage)" \
  TRUE  "backup"    "Sauvegardes avancées (NVMe/SD, rotation, intégrité)" \
  FALSE "watchdog"  "Watchdog système (surveillance + purge logs)" \
  --height=420 --width=900)
```

- Définir des fonctions d'installation par module :
  - `install_module_base_supervision`
  - `install_module_backup`
  - `install_module_watchdog`

Exemple de logique :

```bash
case "$ID" in
  base)     install_module_base_supervision ;;
  backup)   install_module_backup ;;
  watchdog) install_module_watchdog ;;
esac
```

- Ajouter un mode "post-OS" documenté : exécution automatique au premier boot, avec ce menu de modules.

---

## MODULE 1 - SUPERVISION DE BASE

But : garder un cœur simple et safe, activé par défaut.

Contenu :

- Script principal `/usr/local/bin/update-system.sh` (menu GUI/CLI, auto-update, logs, gestion crons).
- Crons par défaut (si module coché) :

```cron
0 6,18 * * * /usr/local/bin/update-system.sh --auto
0 4 * * * find /tmp -type f -atime +7 -delete && find /var/tmp -type f -atime +7 -delete
```

Tâches :

- Isoler la logique "supervision de base" dans une fonction d'installation dédiée.
- S'assurer que le module peut être installé seul sans dépendre des modules avancés.

---

## MODULE 2 - SAUVEGARDES AVANCÉES

But : proposer un module optionnel pour les usages plus exigeants (NVMe, rotation, intégrité).

Fonctionnalités :

- Détection du meilleur disque de sauvegarde (NVMe prioritaire, sinon SD) via l'espace libre.
- Sauvegarde de `/etc`, `/usr/local`, `/home`, `/root` dans un `tar.gz` daté.
- Enregistrement de l'intégrité :
  - hash SHA256 (`*.sha256`)
  - taille (`*.size`)
- Rotation automatique : conserver seulement N sauvegardes (par défaut 3).
- Restauration avec choix de la date + vérification d'intégrité avant extraction.

Idées et exemples à intégrer :

Détection du meilleur disque :

```bash
choose_backup_root() {
  local candidates=()
  mountpoint -q /mnt/nvme1 && candidates+=("/mnt/nvme1")
  mountpoint -q /mnt/nvme2 && candidates+=("/mnt/nvme2")
  [ "${#candidates[@]}" -eq 0 ] && { echo "/"; return; }

  local best="" best_avail=-1
  for path in "${candidates[@]}"; do
    local avail
    avail=$(df -B1 "$path" | awk 'NR==2 {print $4}')
    [ "$avail" -gt "$best_avail" ] && { best_avail="$avail"; best="$path"; }
  done
  echo "${best:-/}"
}
```

Cron de sauvegarde automatique optionnel (si module coché) :

```cron
0 3 * * * /usr/local/bin/update-system.sh --backup-auto
```

Tâches :

- Ajouter un flag `--backup-auto` dans `update-system.sh`.
- Rendre la rotation (nombre de sauvegardes) configurable via variable en haut de script.
- Ajouter un résumé dans les docs : stockage, durée, vérification d'intégrité.

---

## MODULE 3 - WATCHDOG SYSTÈME

But : surveillance périodique du système et nettoyage de logs, utile pour des machines "toujours allumées".

Fonctionnalités :

- Script `/usr/local/bin/watchdog-check.sh` pour :
  - vérifier charge CPU, RAM disponible,
  - pinger une IP ou un domaine critique,
  - vérifier qu'un service vital tourne (`systemctl is-active`).
- Cron toutes les 5 minutes.
- Purge des vieux logs (> 8 jours) pour éviter l'encombrement.

Idées et exemples à intégrer :

Cron recommandé (activé seulement si module coché) :

```cron
*/5 * * * * /usr/local/bin/watchdog-check.sh && find /var/log -name "*.log" -type f -mtime +8 -delete
```

Watchdog minimal (exemple) :

```bash
#!/bin/bash
LOG="/var/log/watchdog-check.log"
{
  echo "===== $(date) ====="
  uptime
  free -h
  ping -c1 1.1.1.1 >/dev/null 2>&1 || echo "Warning: no internet connectivity"
} >> "$LOG" 2>&1
```

Tâches :

- Définir un ensemble minimal de checks par défaut (simple, non intrusif).
- Ajouter une option dans le menu pour afficher le log du watchdog.
- Documenter clairement que ce n'est pas un remplacement d'un monitoring externe complet.

---

## LOGS & HISTORIQUE (MENU + ROTATION)

But : donner de la visibilité sur ce que fait le système, sans saturer le disque.

Fonctionnalités actuelles :

- Logs des mises à jour dans `/var/log/update-system.log`.
- Affichage des logs dans le menu, plus récents en premier (CLI/GUI).

Améliorations prévues :

- Regrouper la logique des logs de supervision dans un répertoire dédié (par ex. `/logs` ou `/mnt/nvmeX/logs`).
- Ajouter un sous-menu "Logs" avec :
  - `update-system.log`
  - `watchdog-check.log`
  - autres logs spécifiques futurs.
- Rotation centralisée :
  - garder 7 jours de logs,
  - nettoyage automatique via cron (module base ou watchdog).

---

## INTÉGRATION POST-OS / RASPBERRY PI IMAGER

But : permettre l'installation des modules directement après flash de l'OS ou au premier boot.

Idées :

- Ajouter dans la doc un snippet "post-OS command" :

FR :
```bash
curl -sL https://raw.githubusercontent.com/thephoenixagency/RaspberryScripts/main/scripts/install-supervision-rpi.fr.sh | bash
```

EN :
```bash
curl -sL https://raw.githubusercontent.com/thephoenixagency/RaspberryScripts/main/scripts/install-supervision-rpi.en.sh | bash
```

- Décrire l'intégration avec la fonctionnalité "Run a script at first boot" de Raspberry Pi Imager.
- Ajouter une page `docs/post-install.fr.md` / `docs/post-install.en.md` dédiée à ce scénario.

---

## DOCUMENTATION & UX

Docs FR / EN :

- Mettre à jour :
  - `docs/supervision.fr.md`
  - `docs/supervision.en.md`
  pour :
  - documenter les modules (Base / Backup / Watchdog),
  - expliquer le menu de sélection au premier lancement,
  - détailler les crons activés par chaque module.

UX du menu :

- Harmoniser les menus CLI/GUI :
  - même ordre d'options,
  - mêmes labels (FR/EN),
  - même logique de retour au menu.
- Ajuster les tailles de fenêtres Zenity et gnome-terminal/lxterminal pour bien tenir sur écran 7–10" sans scroll horizontal.

---

## TESTS & ROBUSTESSE

- Tester les scripts dans 4 cas principaux :
  - Raspberry Pi avec NVMe monté (2 partitions),
  - Raspberry Pi sans NVMe,
  - Raspberry Pi OS (Bookworm),
  - Debian 13 (trixie) sur Pi.
- Vérifier que :
  - en absence de NVMe, aucun montage ne casse le boot ni le menu,
  - la rotation des sauvegardes/logs ne supprime jamais la dernière sauvegarde disponible.
- Ajouter un double-confirm avant restauration (question explicite + nom de la sauvegarde).

---
## ÉTAT ACTUEL

FAIT :
- Installateurs FR/EN : `scripts/install-supervision-rpi.fr.sh` / `scripts/install-supervision-rpi.en.sh`
- Script système : `/usr/local/bin/update-system.sh`
- Menu GUI + CLI (supervision, crons, logs, backup/restore)
- Auto-update + nettoyage temporaires via cron
- Sauvegardes avec rotation, intégrité et restauration par date
- Détection NVMe + fallback SD pour les sauvegardes
- Site de documentation GitHub Pages : https://thephoenixagency.github.io/RaspberryScripts/

À FAIRE :
- Sélection de modules au post-OS (installateur multi-modules)
- Module watchdog dédié (script + cron + docs)
- Intégration documentée avec Raspberry Pi Imager (first-boot script)
```
