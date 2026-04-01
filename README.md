# perfect-woocommerce

![Ubuntu 24.04](https://img.shields.io/badge/Ubuntu-24.04_LTS-E95420?logo=ubuntu&logoColor=white)
![Debian 13](https://img.shields.io/badge/Debian-13_Trixie-A81D33?logo=debian&logoColor=white)
![PHP 8.1–8.5](https://img.shields.io/badge/PHP-8.1_|_8.2_|_8.3_|_8.4_|_8.5-777BB4?logo=php&logoColor=white)
![License MIT](https://img.shields.io/badge/License-MIT-green)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20me%20a%20coffee-djanzin-FFDD00?logo=buy-me-a-coffee&logoColor=black)](https://buymeacoffee.com/djanzin)

Automated, production-ready WooCommerce installer for Ubuntu 24.04 LTS and Debian 13 (Trixie).

---

## English

### What it does

A single bash script that sets up a hardened, high-performance WooCommerce shop from scratch in minutes. Interactive prompts guide you through every configuration option — no manual editing required.

**Stack:**
- **Web server:** Nginx + FastCGI cache (1 GB zone) + Brotli & Gzip compression
- **WooCommerce cache bypass:** Cart, Checkout, My Account and WC-AJAX requests always bypass cache
- **PHP:** PHP-FPM 8.1/8.2/8.3/8.4/8.5 (selectable) + OPcache JIT + `max_input_vars=10000`
- **Database:** MariaDB (tuned: 512 MB InnoDB buffer, query cache disabled for WooCommerce write performance)
- **Object cache:** Redis (256 MB LRU, object cache only)
- **Security:** UFW firewall + Fail2ban (SSH + Nginx + WordPress login + WooCommerce carding jails)
- **Cache management:** Nginx Helper plugin (automatic FastCGI cache purge)
- **CLI:** WP-CLI with `wpcli` shortcut
- **SSL:** Optional Let's Encrypt / Certbot (automatic HTTPS redirect) — strongly recommended for WooCommerce
- **Backups:** Daily MariaDB dumps with 7-day rotation
- **WooCommerce Action Scheduler:** System cron every 2 minutes (replaces WP-Cron for reliability)
- **Reverse Proxy mode:** Auto-configures for NPM/Traefik/Cloudflare (Real-IP, HTTPS URLs, Fail2ban whitelist)
- **phpMyAdmin:** Optional, accessible via subdomain `phpmyadmin.domain`
- **FileBrowser:** Optional web file manager via subdomain `files.domain`

### Requirements

- Ubuntu 24.04 LTS **or** Debian 13 (Trixie)
- Root / sudo access
- A domain name pointing to the server (required for SSL; strongly recommended for WooCommerce)

### One-line install (directly from GitHub)

```bash
curl -fsSL https://raw.githubusercontent.com/djanzin/perfect-woocommerce/main/install-woocommerce.sh -o /tmp/install-wc.sh && sudo bash /tmp/install-wc.sh
```

With flags (non-interactive):

```bash
curl -fsSL https://raw.githubusercontent.com/djanzin/perfect-woocommerce/main/install-woocommerce.sh -o /tmp/install-wc.sh && sudo bash /tmp/install-wc.sh --domain example.com --email admin@example.com --ssl --currency EUR --country DE
```

The script will interactively ask for:
- Domain name & admin email
- Site title & admin username
- PHP version (8.1 / 8.2 / **8.3** / 8.4 / 8.5 ⚠️ dev)
- PHP memory limit (128M / 256M / **512M** / 1024M)
- WordPress language (default: `de_DE`)
- Timezone (default: `Europe/Berlin`)
- SSL via Let's Encrypt (yes/no)
- Shop currency (EUR / USD / GBP / CHF)
- WooCommerce base country (e.g. `DE`, `AT`, `CH`, `US:CA`)

### Non-interactive usage

All options can be passed as flags to skip the interactive prompts:

```bash
sudo bash install-woocommerce.sh \
  --domain example.com \
  --email admin@example.com \
  --title "My Shop" \
  --admin-user admin \
  --php 8.3 \
  --memory 512M \
  --lang en_US \
  --timezone America/New_York \
  --ssl \
  --currency USD \
  --country US
```

### CLI options

| Flag | Description | Default |
|------|-------------|---------|
| `--domain` | Domain name (e.g. `example.com`) | — |
| `--email` | WordPress admin email | — |
| `--title` | WordPress site title | `My WooCommerce Shop` |
| `--admin-user` | WordPress admin username | `admin` |
| `--php` | PHP version (`8.1`, `8.2`, `8.3`, `8.4`, `8.5`) | `8.3` |
| `--memory` | PHP memory limit (`128M`, `256M`, `512M`, `1024M`) | `512M` |
| `--lang` | WordPress language code | `de_DE` |
| `--timezone` | PHP/WordPress timezone | `Europe/Berlin` |
| `--ssl` | Install SSL certificate via Certbot | `false` |
| `--currency` | Shop currency (`EUR`, `USD`, `GBP`, `CHF`) | `EUR` |
| `--country` | WooCommerce base country/state (e.g. `DE`, `US:CA`) | `DE` |
| `--english` | English prompts and status messages | `false` |

### What gets installed (10 steps)

1. System update + base tools + **swap file** (auto-created if < 1 GB available)
2. Nginx + FastCGI cache + **Brotli compression** + cache purge module + WooCommerce bypass rules
3. PHP-FPM (selected version) + OPcache JIT (tracing mode, 128 MB JIT buffer) + `max_input_vars=10000`
4. MariaDB (512 MB InnoDB buffer, query cache disabled, slow query log, hardened)
5. Redis object cache (256 MB LRU, no persistence)
6. UFW firewall + Fail2ban (SSH, Nginx, WordPress login + WooCommerce carding jails)
7. WordPress core (latest) + `wp-config.php` (randomized table prefix, secure salts, WC constants)
8. WP-CLI + Redis Cache plugin + **Nginx Helper** plugin (auto-configured)
9. **WooCommerce** — install, activate, configure currency/country, create shop pages, run DB migration
10. Log rotation + system cron + **Action Scheduler** (every 2 min) + **daily DB backups**

### Credentials

All generated credentials (admin password, database, Redis) are saved to:

```
/root/.wp_install_credentials_<domain>.txt  (chmod 600)
```

Database backups are stored in:

```
/root/backups/mysql/  (daily, 7-day rotation)
```

### Update

```bash
curl -fsSL https://raw.githubusercontent.com/djanzin/perfect-woocommerce/main/update-woocommerce.sh -o /tmp/update-wc.sh && sudo bash /tmp/update-wc.sh
```

With flags:

```bash
sudo bash update-woocommerce.sh --all          # WordPress + WooCommerce + Plugins + Themes + System + WP-CLI + SSL
sudo bash update-woocommerce.sh                # WordPress + WooCommerce + Plugins + Themes + Cache only
sudo bash update-woocommerce.sh --system       # additionally: system packages
sudo bash update-woocommerce.sh --wpcli        # additionally: WP-CLI
sudo bash update-woocommerce.sh --ssl          # additionally: renew SSL certificate
```

| Flag | Description |
|------|-------------|
| `--all` | Run all updates |
| `--system` | Update system packages via apt |
| `--wpcli` | Update WP-CLI to latest version |
| `--ssl` | Renew SSL certificate via Certbot |
| `--wp-path` | Custom WordPress path (auto-detected if omitted) |
| `--english` | English status messages |

The update script automatically runs a **WooCommerce database migration** after plugin updates and rebuilds product lookup tables.

### Reset

Removes everything installed by this script — WordPress, WooCommerce, Nginx, PHP-FPM, MariaDB, Redis, Fail2ban, WP-CLI, phpMyAdmin, FileBrowser, SSL certificates, cron jobs (including Action Scheduler) and swap. Runs without any prompts.

```bash
curl -fsSL https://raw.githubusercontent.com/djanzin/perfect-woocommerce/main/reset-woocommerce.sh -o /tmp/reset-wc.sh && sudo bash /tmp/reset-wc.sh
```

Use `--english` for English output:

```bash
sudo bash reset-woocommerce.sh --english
```

> **Warning:** This is irreversible. All data including the database, orders, products and uploaded files will be permanently deleted.

<a href="https://www.buymeacoffee.com/djanzin"><img src="https://img.buymeacoffee.com/button-api/?text=Buy%20me%20a%20coffee&emoji=%E2%98%95&slug=djanzin&button_colour=00354d&font_colour=ffffff&font_family=Cookie&outline_colour=ffffff&coffee_colour=FFDD00" /></a>

---

## Deutsch

### Was es macht

Ein einzelnes Bash-Script, das einen abgesicherten, leistungsstarken WooCommerce-Shop in wenigen Minuten von Grund auf einrichtet. Interaktive Abfragen führen durch alle Konfigurationsoptionen — kein manuelles Editieren nötig.

**Stack:**
- **Webserver:** Nginx + FastCGI-Cache (1 GB Zone) + Brotli & Gzip Komprimierung
- **WooCommerce Cache-Bypass:** Warenkorb, Kasse, Mein Konto und WC-AJAX-Anfragen umgehen immer den Cache
- **PHP:** PHP-FPM 8.1/8.2/8.3/8.4/8.5 (wählbar) + OPcache JIT + `max_input_vars=10000`
- **Datenbank:** MariaDB (optimiert: 512 MB InnoDB Buffer, Query Cache deaktiviert für WooCommerce-Schreibleistung)
- **Object Cache:** Redis (256 MB LRU, nur Cache)
- **Sicherheit:** UFW Firewall + Fail2ban (SSH + Nginx + WordPress-Login + WooCommerce Carding Jail)
- **Cache-Verwaltung:** Nginx Helper Plugin (automatische FastCGI-Cache-Invalidierung)
- **CLI:** WP-CLI mit `wpcli` Shortcut
- **SSL:** Optionales Let's Encrypt / Certbot (automatischer HTTPS-Redirect) — für WooCommerce dringend empfohlen
- **Backups:** Tägliche MariaDB-Dumps mit 7-Tage-Rotation
- **WooCommerce Action Scheduler:** System-Cron alle 2 Minuten (ersetzt WP-Cron für Zuverlässigkeit)
- **Reverse Proxy Modus:** Automatische Konfiguration für NPM/Traefik/Cloudflare (Real-IP, HTTPS-URLs, Fail2ban Whitelist)
- **phpMyAdmin:** Optional, erreichbar über Subdomain `phpmyadmin.domain`
- **FileBrowser:** Optionaler Web-Dateimanager über Subdomain `files.domain`

### Voraussetzungen

- Ubuntu 24.04 LTS **oder** Debian 13 (Trixie)
- Root / sudo Zugang
- Ein Domainname der auf den Server zeigt (erforderlich für SSL; für WooCommerce dringend empfohlen)

### Ein-Befehl-Installation (direkt von GitHub)

```bash
curl -fsSL https://raw.githubusercontent.com/djanzin/perfect-woocommerce/main/install-woocommerce.sh -o /tmp/install-wc.sh && sudo bash /tmp/install-wc.sh
```

Mit Flags (nicht-interaktiv):

```bash
curl -fsSL https://raw.githubusercontent.com/djanzin/perfect-woocommerce/main/install-woocommerce.sh -o /tmp/install-wc.sh && sudo bash /tmp/install-wc.sh --domain example.com --email admin@example.com --ssl --currency EUR --country DE
```

Das Script fragt interaktiv nach:
- Domain & Admin-E-Mail
- Site-Titel & Admin-Benutzername
- PHP-Version (8.1 / 8.2 / **8.3** / 8.4 / 8.5 ⚠️ dev)
- PHP Memory Limit (128M / 256M / **512M** / 1024M)
- WordPress-Sprache (Standard: `de_DE`)
- Zeitzone (Standard: `Europe/Berlin`)
- SSL via Let's Encrypt (ja/nein)
- Shop-Währung (EUR / USD / GBP / CHF)
- WooCommerce Basisland (z.B. `DE`, `AT`, `CH`, `US:CA`)

### Nicht-interaktive Nutzung

Alle Optionen können als Flags übergeben werden, um die interaktiven Abfragen zu überspringen:

```bash
sudo bash install-woocommerce.sh \
  --domain example.com \
  --email admin@example.com \
  --title "Mein Shop" \
  --admin-user admin \
  --php 8.3 \
  --memory 512M \
  --lang de_DE \
  --timezone Europe/Berlin \
  --ssl \
  --currency EUR \
  --country DE
```

### Alle Optionen

| Flag | Beschreibung | Standard |
|------|-------------|---------|
| `--domain` | Domainname (z.B. `example.com`) | — |
| `--email` | WordPress Admin-E-Mail | — |
| `--title` | WordPress-Site-Titel | `My WooCommerce Shop` |
| `--admin-user` | WordPress Admin-Benutzername | `admin` |
| `--php` | PHP-Version (`8.1`, `8.2`, `8.3`, `8.4`, `8.5`) | `8.3` |
| `--memory` | PHP Memory Limit (`128M`, `256M`, `512M`, `1024M`) | `512M` |
| `--lang` | WordPress-Sprachcode | `de_DE` |
| `--timezone` | PHP/WordPress-Zeitzone | `Europe/Berlin` |
| `--ssl` | SSL-Zertifikat via Certbot installieren | `false` |
| `--currency` | Shop-Währung (`EUR`, `USD`, `GBP`, `CHF`) | `EUR` |
| `--country` | WooCommerce Basisland/-staat (z.B. `DE`, `US:CA`) | `DE` |
| `--english` | Englische Ausgabe für alle Prompts und Statusmeldungen | `false` |

### Was installiert wird (10 Schritte)

1. System-Update + Basis-Tools + **Swap-Datei** (automatisch angelegt falls < 1 GB vorhanden)
2. Nginx + FastCGI-Cache + **Brotli-Komprimierung** + Cache-Purge-Modul + WooCommerce Bypass-Regeln
3. PHP-FPM (gewählte Version) + OPcache JIT (Tracing-Modus, 128 MB JIT-Buffer) + `max_input_vars=10000`
4. MariaDB (512 MB InnoDB Buffer, Query Cache deaktiviert, Slow Query Log, gehärtet)
5. Redis Object Cache (256 MB LRU, keine Persistenz)
6. UFW Firewall + Fail2ban (SSH-, Nginx-, WordPress-Login- und WooCommerce-Carding-Jail)
7. WordPress Core (aktuell) + `wp-config.php` (zufälliger Tabellen-Präfix, sichere Salts, WC-Konstanten)
8. WP-CLI + Redis Cache Plugin + **Nginx Helper** Plugin (automatisch konfiguriert)
9. **WooCommerce** — installieren, aktivieren, Währung/Land konfigurieren, Shop-Seiten erstellen, DB-Migration
10. Log-Rotation + System-Cron + **Action Scheduler** (alle 2 Min.) + **tägliche DB-Backups**

### Zugangsdaten

Alle generierten Zugangsdaten (Admin-Passwort, Datenbank, Redis) werden gespeichert in:

```
/root/.wp_install_credentials_<domain>.txt  (chmod 600)
```

Datenbank-Backups befinden sich in:

```
/root/backups/mysql/  (täglich, 7 Tage Rotation)
```

### Update

```bash
curl -fsSL https://raw.githubusercontent.com/djanzin/perfect-woocommerce/main/update-woocommerce.sh -o /tmp/update-wc.sh && sudo bash /tmp/update-wc.sh
```

Mit Flags:

```bash
sudo bash update-woocommerce.sh --all          # WordPress + WooCommerce + Plugins + Themes + System + WP-CLI + SSL
sudo bash update-woocommerce.sh                # Nur WordPress + WooCommerce + Plugins + Themes + Cache
sudo bash update-woocommerce.sh --system       # Zusätzlich: System-Pakete
sudo bash update-woocommerce.sh --wpcli        # Zusätzlich: WP-CLI
sudo bash update-woocommerce.sh --ssl          # Zusätzlich: SSL-Zertifikat erneuern
```

| Flag | Beschreibung |
|------|-------------|
| `--all` | Alle Updates ausführen |
| `--system` | System-Pakete via apt aktualisieren |
| `--wpcli` | WP-CLI auf neueste Version aktualisieren |
| `--ssl` | SSL-Zertifikat via Certbot erneuern |
| `--wp-path` | Eigener WordPress-Pfad (wird automatisch erkannt falls nicht angegeben) |
| `--english` | Englische Statusmeldungen |

Das Update-Script führt nach Plugin-Updates automatisch eine **WooCommerce Datenbank-Migration** durch und baut Produkt-Lookup-Tabellen neu auf.

### Reset

Entfernt alles was dieses Script installiert hat — WordPress, WooCommerce, Nginx, PHP-FPM, MariaDB, Redis, Fail2ban, WP-CLI, phpMyAdmin, FileBrowser, SSL-Zertifikate, Cron-Jobs (inkl. Action Scheduler) und Swap. Läuft ohne Rückfragen durch.

```bash
curl -fsSL https://raw.githubusercontent.com/djanzin/perfect-woocommerce/main/reset-woocommerce.sh -o /tmp/reset-wc.sh && sudo bash /tmp/reset-wc.sh
```

Mit `--english` für englische Ausgabe:

```bash
sudo bash reset-woocommerce.sh --english
```

> **Warnung:** Dieser Vorgang ist unwiderruflich. Alle Daten einschließlich Datenbank, Bestellungen, Produkte und hochgeladener Dateien werden dauerhaft gelöscht.

<a href="https://www.buymeacoffee.com/djanzin"><img src="https://img.buymeacoffee.com/button-api/?text=Buy%20me%20a%20coffee&emoji=%E2%98%95&slug=djanzin&button_colour=00354d&font_colour=ffffff&font_family=Cookie&outline_colour=ffffff&coffee_colour=FFDD00" /></a>

---

## License

MIT
