# 🧰 Menu de Supervision Raspberry Pi (GUI + CLI) – FR

Ce script fournit un menu de **supervision** complet pour Raspberry Pi :

- Mises à jour automatiques via cron (`apt update && apt upgrade -y`)
- Nettoyage automatique des fichiers temporaires (`/tmp`, `/var/tmp`)
- Menu graphique (Zenity) et menu CLI (multi‑options)
- Gestion des crons root (lister, ajouter, supprimer, remplacer)
- Consultation des logs des mises à jour (les plus récents en haut)
- Sauvegardes automatiques du système + scripts admins
  - Détection du meilleur disque (NVMe ou carte SD)
  - Rotation des sauvegardes (3 sauvegardes max)
  - Vérification d’intégrité (hash SHA256 + taille)
  - Restauration par date (type “point de restauration”)
- Gestion centralisée des logs avec rétention de 7 jours

Le script système installé est : `/usr/local/bin/update-system.sh`.

---

## Scripts associés

- Installateur FR : [`../scripts/install-supervision.fr.sh`](../scripts/install-supervision-rpi.fr.sh)
- Installateur EN : [`../scripts/install-supervision.en.sh`](../scripts/install-supervision-rpi.en.sh)

---

## Installation

1. Copier `../scripts/install-supervision.fr.sh` sur le Raspberry Pi.
2. Rendre le script exécutable :

   ```bash
   chmod +x install-supervision.fr.sh
