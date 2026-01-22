<p align="center">
  <img src="assets/logo.jpeg" alt="RaspberryScripts" width="400"/>
</p>

<h1 align="center">Raspberry Pi Scripts Hub</h1>

<p align="center">
  <a href="https://ThePhoenixAgency.github.io/RaspberryScripts/"><strong>🌐 View Documentation Website</strong></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Bash-4EAA25?style=for-the-badge&logo=gnu-bash&logoColor=white" alt="Bash"/>
  <img src="https://img.shields.io/badge/Raspberry%20Pi-A22846?style=for-the-badge&logo=raspberry-pi&logoColor=white" alt="Raspberry Pi"/>
  <img src="https://img.shields.io/badge/Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black" alt="Linux"/>
  <img src="https://img.shields.io/badge/Shell_Script-121011?style=for-the-badge&logo=gnu-bash&logoColor=white" alt="Shell"/>
</p>

---

## 🇫🇷 Français

Bienvenue dans **Raspberry Pi Scripts Hub**, ton centre de scripts d’administration pour Raspberry Pi.

Chaque script a :

- Un fichier Bash dans `scripts/`
- Une documentation dédiée dans `docs/` (FR + EN)
- Une intégration prévue avec le site de documentation GitHub Pages :  
  👉 [`index.html`](https://ThePhoenixAgency.github.io/RaspberryScripts/)

> **📁 Scripts Bash :** dossier `scripts/`  
> **📝 Documentation détaillée :** dossier `docs/`  
> **🌐 Site de doc :** `ThePhoenixAgency.github.io/RaspberryScripts`

### Scripts disponibles

- 🧰 **Menu de Supervision Raspberry Pi (GUI + CLI)**  
  Supervision complète du Raspberry Pi :
  - Mises à jour automatiques (cron)
  - Nettoyage des fichiers temporaires
  - Menu CLI + GUI (zenity)
  - Gestion des crons root (afficher / ajouter / supprimer / remplacer)
  - Sauvegardes automatiques avec :
    - Détection du meilleur disque (NVMe ou SD)
    - Rotation des sauvegardes (3 sauvegardes max)
    - Vérification d’intégrité (hash + taille)
    - Restauration par date (type “point de restauration”)
  - Logs centralisés avec rétention 7 jours

  - 🇫🇷 Documentation FR : [`docs/Supervision.fr.md`](docs/Supervision.fr.md)  
  - 🇬🇧 Documentation EN : [`docs/Supervision.en.md`](docs/Supervision.en.md)

---

## 🇬🇧 English

Welcome to **Raspberry Pi Scripts Hub**, your admin scripts hub for Raspberry Pi.

Each script ships with:

- A Bash script in `scripts/`
- A dedicated `.md` documentation file in `docs/` (FR + EN)
- A static documentation website hosted on GitHub Pages:  
  👉 [`index.html`](https://ThePhoenixAgency.github.io/RaspberryScripts/)

> **📁 Bash scripts live in:** `scripts/`  
> **📝 Detailed docs live in:** `docs/`  
> **🌐 Documentation website:** `ThePhoenixAgency.github.io/RaspberryScripts`

### Available scripts

- 🧰 **Raspberry Pi Supervision Menu (GUI + CLI)**  
  Full supervision of your Raspberry Pi:
  - Automatic updates via cron
  - Temporary files cleanup
  - CLI + GUI menu (zenity)
  - Root cron management (list / add / delete / replace)
  - Automated backups with:
    - Best disk detection (NVMe or SD)
    - Backup rotation (keep 3 backups)
    - Integrity check (hash + size)
    - Restore by date (Windows “restore point” style)
  - Centralized logs with 7‑day retention

  - 🇫🇷 FR docs: [`docs/Supervision.fr.md`](docs/Supervision.fr.md)  
  - 🇬🇧 EN docs: [`docs/Supervision.en.md`](docs/Supervision.en.md)
