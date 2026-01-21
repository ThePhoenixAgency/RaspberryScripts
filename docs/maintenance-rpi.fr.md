# 🧰 Menu de maintenance Raspberry Pi (GUI + CLI) – FR

Ce script fournit un menu de maintenance complet pour Raspberry Pi :

- Mise à jour automatique 2× par jour (`apt update && apt upgrade -y`)
- Menu graphique (Zenity) et menu CLI (1–9)
- Gestion des crons root (lister, ajouter, supprimer, remplacer)
- Consultation du log des mises à jour (`/var/log/update-system.log`)

---

## Scripts associés

- Installateur FR : `../scripts/install-maintenance-rpi.fr.sh`
- Installateur EN : `../scripts/install-maintenance-rpi.en.sh`

Le script système installé est : `/usr/local/bin/update-system.sh`.

---

## Installation

1. Copier le fichier `../scripts/install-maintenance-rpi.fr.sh` sur le Raspberry Pi.
2. Rendre le script exécutable :

```bash
chmod +x install-maintenance-rpi.fr.sh

    Exécuter le script d'installation :

bash
./install-maintenance-rpi.fr.sh

Utilisation
Menu GUI / CLI

Depuis le bureau :

    Double-cliquer sur l'icône « Maintenance (GUI+CLI) »

    ou exécuter :

bash
/usr/local/bin/update-system.sh

Le script tente d'abord le GUI, puis bascule sur le CLI si nécessaire.
Fonctions principales

    Mettre à jour le système

    Redémarrer / éteindre

    Afficher les crons root

    Ajouter / supprimer / remplacer des lignes cron root

    Afficher le log des mises à jour

Cron d'auto‑mise à jour

Après installation, le crontab root contient :

text
# Mise à jour automatique 2x/jour à 06h et 18h
0 6,18 * * * /usr/local/bin/update-system.sh --auto

Pour afficher le cron :

bash
sudo crontab -l

Pour afficher le log :

bash
sudo tail -n 50 /var/log/update-system.log