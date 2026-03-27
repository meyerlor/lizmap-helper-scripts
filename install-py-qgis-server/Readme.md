# QGIS Server Stack – Installation Guide

Complete installation guide for a production-ready **QGIS Server** stack on Ubuntu (LTS), consisting of:

- **QGIS Server** (LTR) via the official QGIS APT repository
- **py-qgis-server** – Python-based application server with worker pool and Lizmap API
- **Lizmap Web Client (LWC)** – Web GIS frontend
- **QGIS Plugin Manager** – server-side plugin management (Lizmap Server, AtlasPrint, WFS Output Extension)

> **Prerequisites:** A fresh Ubuntu 22.04/24.04 LTS installation is assumed. All commands are run as root or with `sudo`.

> **Scope:** This guide covers the installation and configuration of QGIS Server and py-qgis-server. **Nginx virtual host configuration and detailed Lizmap Web Client setup are not covered here** – please refer to the [official Lizmap documentation](https://docs.lizmap.com/current/en/install/linux.html) for those steps.

---

## Table of Contents

1. [Add QGIS Repository & Install Dependencies](#1-add-qgis-repository--install-dependencies)
2. [Set Up Virtual Display (Xvfb)](#2-set-up-virtual-display-xvfb)
3. [Install py-qgis-server](#3-install-py-qgis-server)
4. [Configure py-qgis-server](#4-configure-py-qgis-server)
5. [Set Up QGIS Systemd Service](#5-set-up-qgis-systemd-service)
6. [Install QGIS Plugins](#6-install-qgis-plugins)
7. [Configure Locale & Timezone](#7-configure-locale--timezone)
8. [Install Lizmap Web Client](#8-install-lizmap-web-client)

---

## 1. Add QGIS Repository & Install Dependencies

Import the official QGIS GPG signing key and add the LTR package repository. The Ubuntu codename is detected automatically.

```bash
sudo wget -O /etc/apt/keyrings/qgis-archive-keyring.gpg https://download.qgis.org/downloads/qgis-archive-keyring.gpg
echo -e "Types: deb deb-src\nURIs: https://qgis.org/ubuntu-ltr\nSuites: $(lsb_release -cs)\nArchitectures: amd64\nComponents: main\nSigned-By: /etc/apt/keyrings/qgis-archive-keyring.gpg" | sudo tee /etc/apt/sources.list.d/qgis.sources
```

Update package sources and install all required packages (QGIS, QGIS Server, PHP 8.3 for LWC, Nginx, Certbot, NTP, etc.):

```bash
sudo apt update && sudo apt dist-upgrade && sudo apt install certbot python3-certbot-nginx python3-pip unzip gnupg software-properties-common ntp ntpdate php8.3-fpm php8.3-cli php8.3-bz2 php8.3-curl php8.3-gd php8.3-intl php8.3-mbstring php8.3-pgsql php8.3-sqlite3 php8.3-xml php8.3-ldap php8.3-redis curl openssl libssl3 nginx-full nginx nginx-common qgis qgis-server python3-qgis python3-venv python3-psutil xvfb
```

---

## 2. Set Up Virtual Display (Xvfb)

QGIS Server requires a display for server-side printing (Atlas, GetPrint). Xvfb provides a virtual framebuffer display and is configured as a systemd service.

```bash
echo -e "[Unit]\nDescription=X Virtual Frame Buffer Service\nAfter=network.target\n\n[Service]\nExecStart=/usr/bin/Xvfb :99 -screen 0 1024x768x24 -ac +extension GLX +render -noreset\n\n[Install]\nWantedBy=multi-user.target" | sudo tee /etc/systemd/system/xvfb.service && sudo systemctl enable --now xvfb.service && sudo systemctl status xvfb.service
```

---

## 3. Install py-qgis-server

py-qgis-server runs in an isolated Python virtual environment with access to the system site-packages (required for QGIS Python bindings).

```bash
set -e && python3 -m venv /opt/local/py-qgis-server --system-site-packages && /opt/local/py-qgis-server/bin/pip install -U pip setuptools wheel pysocks typing py-qgis-server
```

Create required directories and the restart monitor file. `py-qgis-restartmon` is watched by the server – a `touch` on this file triggers a graceful reload of all workers (see also `qgis-reload` below).

```bash
mkdir -p /srv/qgis/plugins /srv/qgis/config /var/log/qgis /var/lib/py-qgis-server /srv/data
touch /var/lib/py-qgis-server/py-qgis-restartmon && chmod 664 /var/lib/py-qgis-server/py-qgis-restartmon
```

Create the `qgis-reload` helper script, which triggers a worker reload via the restart monitor (e.g. after plugin updates):

```bash
echo -e '#!/bin/bash\n\n touch /var/lib/py-qgis-server/py-qgis-restartmon' | sudo tee /usr/bin/qgis-reload && sudo chmod 750 /usr/bin/qgis-reload
```

---

## 4. Configure py-qgis-server

### Main Configuration (`/srv/qgis/server.conf`)

The server listens on port 7200 (localhost only), manages 4 worker processes, and exposes the Lizmap API. `rootdir` defines the root directory for QGIS project files.

```bash
sudo mkdir -p /srv/qgis && sudo mkdir -p /srv/data && echo -e "#\n# py-qgis-server configuration\n# https://docs.3liz.org/py-qgis-server/\n#\n[server]\nport = 7200\ninterfaces = 127.0.0.1\nworkers = 4\npluginpath = /srv/qgis/plugins\ntimeout = 200\nrestartmon = /var/lib/py-qgis-server/py-qgis-restartmon\n[logging]\nlevel = info\n[projects.cache]\nstrict_check = false\nrootdir = /srv/data\nsize = 50\nadvanced_report = no\n[monitor:amqp]\nrouting_key =\ndefault_routing_key=\nhost =\n[api.endpoints]\nlizmap_api=/lizmap\n[api.enabled]\nlizmap_api=yes" | sudo tee /srv/qgis/server.conf
```

### Environment Variables (`/srv/qgis/config/qgis-service.env`)

Sets QGIS-specific environment variables: locale, GDAL cache, authentication database path, and server behaviour. `QGIS_SERVER_FORCE_READONLY_LAYERS` and `QGIS_SERVER_TRUST_LAYER_METADATA` improve performance by skipping write locks and metadata re-reads at project load time.

```bash
sudo mkdir -p /srv/qgis/config && echo -e "LC_ALL=en_US.UTF-8\nLANG=en_US.UTF-8\nDISPLAY=:99\nQGIS_OPTIONS_PATH=/srv/qgis/\nQGIS_AUTH_DB_DIR_PATH=/srv/qgis/\nGDAL_CACHEMAX=2048\nQGIS_SERVER_CACHE_SIZE=2048\nQGIS_SERVER_LIZMAP_REVEAL_SETTINGS=TRUE\nQGIS_SERVER_FORCE_READONLY_LAYERS=TRUE\nQGIS_SERVER_TRUST_LAYER_METADATA=TRUE\nQGIS_SERVER_APPLICATION_NAME=qgis-server" | sudo tee /srv/qgis/config/qgis-service.env
```

---

## 5. Set Up QGIS Systemd Service

Create, enable and start the systemd unit for py-qgis-server. `ExecReload` uses the `qgis-reload` script for a graceful worker reload without a full service restart.

```bash
sudo mkdir -p /var/log/qgis && echo -e "[Unit]\nDescription=QGIS Server (py-qgis-server)\nAfter=network.target\n[Service]\nType=simple\nExecStart=/opt/local/py-qgis-server/bin/qgisserver -c /srv/qgis/server.conf\nExecReload=/usr/bin/qgis-reload\nKillMode=control-group\nKillSignal=SIGTERM\nTimeoutStopSec=10\nRestart=always\nStandardOutput=append:/var/log/qgis/qgis-server.log\nStandardError=inherit\nSyslogIdentifier=qgis\nEnvironmentFile=/srv/qgis/config/qgis-service.env\nUser=root\nLimitNOFILE=4096\n[Install]\nWantedBy=multi-user.target" | sudo tee /etc/systemd/system/qgis.service && sudo systemctl enable qgis && sudo service qgis start
```

Verify the service is running:

```bash
sudo systemctl status qgis
```

---

## 6. Install QGIS Plugins

`qgis-plugin-manager` downloads and manages server-side QGIS plugins. The following plugins are installed:

| Plugin | Purpose |
|---|---|
| `atlasprint` | Server-side atlas printing via API |
| `Lizmap server` | Lizmap-specific server extensions |
| `wfsOutputExtension` | Extended WFS output formats (GeoJSON, CSV, ...) |

```bash
sudo mkdir -p /srv/qgis/plugins && cd /srv/qgis/plugins && sudo pip3 install qgis-plugin-manager --break-system-packages && sudo qgis-plugin-manager init && sudo qgis-plugin-manager update && sudo qgis-plugin-manager install atlasprint && sudo qgis-plugin-manager install "Lizmap server" && sudo qgis-plugin-manager install wfsOutputExtension && sudo chmod 755 /srv/qgis/plugins/ -R && sudo chown www-data:www-data /srv/qgis/plugins/ -R
```

---

## 7. Configure Locale & Timezone

```bash
locale-gen de_DE.UTF-8 && dpkg-reconfigure locales && dpkg-reconfigure tzdata
```

---

## 8. Install Lizmap Web Client

The latest LWC release is retrieved via the GitHub API and downloaded directly to `/var/www/`:

```bash
cd /var/www/ && curl -s https://api.github.com/repos/3liz/lizmap-web-client/releases/latest | grep "browser_download_url.*zip" | cut -d : -f 2,3 | tr -d \" | wget -qi -
```

> **Next steps:** After downloading, unzip the archive, configure your Nginx virtual host, and adjust `lizmap/var/config/lizmapConfig.ini.php` and `localconfig.ini.php`. Detailed instructions are available in the [official Lizmap documentation](https://docs.lizmap.com/current/en/install/linux.html). **Nginx virtual host configuration is not covered in this guide.**

### Lizmap: QGIS Server Connection

After the first login to Lizmap, navigate to **Administration → Lizmap Configuration → QGIS Server** and set the following URLs:

| Setting | Value |
|---|---|
| URL of QGIS Server | `http://127.0.0.1:7200/ows/` |
| Base URL of Lizmap Plugin API | `http://127.0.0.1:7200/lizmap/` |

---

## Directory Structure (Overview)

```
/srv/
├── qgis/
│   ├── server.conf          # py-qgis-server main configuration
│   ├── plugins/             # QGIS Server plugins
│   └── config/
│       └── qgis-service.env # Environment variables for the service
└── data/                    # QGIS project files (rootdir)

/opt/local/py-qgis-server/   # Python virtual environment
/var/log/qgis/               # Log files
/var/lib/py-qgis-server/
└── py-qgis-restartmon        # Touch file for graceful worker reload
/usr/bin/qgis-reload          # Helper script for worker reload
/var/www/                     # Lizmap Web Client
```

---

## Further Reading

- [py-qgis-server Documentation](https://docs.3liz.org/py-qgis-server/)
- [Lizmap Web Client Documentation](https://docs.lizmap.com/)
- [QGIS Server Documentation](https://docs.qgis.org/latest/en/docs/server_manual/)
- [QGIS Plugin Manager](https://github.com/3liz/qgis-plugin-manager)
