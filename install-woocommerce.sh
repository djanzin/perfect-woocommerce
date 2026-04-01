#!/usr/bin/env bash
# =============================================================================
#  WooCommerce Production Installer
#  Stack: Ubuntu LTS / Debian · Nginx + FastCGI Cache · PHP-FPM + OPcache
#         MariaDB · Redis Object Cache · UFW · Fail2ban · WP-CLI · WooCommerce
# =============================================================================
# Usage:
#   sudo bash install-woocommerce.sh
#   sudo bash install-woocommerce.sh --domain example.com --email admin@example.com \
#     --php 8.4 --memory 512M --lang de_DE --timezone Europe/Berlin --ssl \
#     --currency EUR --country DE
#
# Tested on: Ubuntu 24.04 LTS · Debian 13 (Trixie)
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# ─── Colour helpers ───────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }
section() { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${RESET}"; \
            echo -e "${BOLD}${CYAN}  $*${RESET}"; \
            echo -e "${BOLD}${CYAN}══════════════════════════════════════════${RESET}"; }

# ─── Pre-scan for --english (needed before language block is set up) ──────────
_ENGLISH_PRESCAN=false
for _arg in "$@"; do [[ "$_arg" == "--english" ]] && _ENGLISH_PRESCAN=true && break; done

# ─── Root check ───────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  if [[ "$_ENGLISH_PRESCAN" == true ]]; then
    error "This script must be run as root. Please use 'sudo bash $0'."
  else
    error "Dieses Script muss als root ausgeführt werden. Bitte 'sudo bash $0' verwenden."
  fi
fi

# ─── OS detection ─────────────────────────────────────────────────────────────
if grep -qi 'ubuntu' /etc/os-release; then
  OS_TYPE="ubuntu"
elif grep -qi 'debian' /etc/os-release; then
  OS_TYPE="debian"
else
  if [[ "$_ENGLISH_PRESCAN" == true ]]; then
    error "Unsupported OS. Ubuntu 24.04+ or Debian 13+ required."
  else
    error "Nicht unterstütztes OS. Ubuntu 24.04+ oder Debian 13+ erforderlich."
  fi
fi
if [[ "$_ENGLISH_PRESCAN" == true ]]; then
  info "Detected OS: $OS_TYPE"
else
  info "Erkanntes Betriebssystem: $OS_TYPE"
fi

# ─── Default configuration ────────────────────────────────────────────────────
WP_DOMAIN=""
WP_ADMIN_EMAIL=""
WP_SITE_TITLE="My WooCommerce Shop"
WP_ADMIN_USER="admin"
WP_DIR="/var/www/wordpress"
NGINX_FASTCGI_CACHE_DIR="/var/cache/nginx/fastcgi"
PHP_VERSION="8.3"
PHP_MEMORY_LIMIT="512M"
WP_LANG=""
WP_TIMEZONE="Europe/Berlin"
INSTALL_SSL=false
INSTALL_PHPMYADMIN=false
INSTALL_FILEBROWSER=false
REVERSE_PROXY=false
ENGLISH=false
WC_CURRENCY="EUR"
WC_COUNTRY="DE"

# ─── Parse arguments ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain)       WP_DOMAIN="$2";        shift 2 ;;
    --email)        WP_ADMIN_EMAIL="$2";   shift 2 ;;
    --title)        WP_SITE_TITLE="$2";    shift 2 ;;
    --admin-user)   WP_ADMIN_USER="$2";    shift 2 ;;
    --php)          PHP_VERSION="$2";      shift 2 ;;
    --memory)       PHP_MEMORY_LIMIT="$2"; shift 2 ;;
    --lang)         WP_LANG="$2";          shift 2 ;;
    --timezone)     WP_TIMEZONE="$2";      shift 2 ;;
    --currency)     WC_CURRENCY="$2";      shift 2 ;;
    --country)      WC_COUNTRY="$2";       shift 2 ;;
    --ssl)          INSTALL_SSL=true;        shift   ;;
    --phpmyadmin)    INSTALL_PHPMYADMIN=true;  shift   ;;
    --filebrowser)    INSTALL_FILEBROWSER=true;  shift   ;;
    --reverse-proxy)  REVERSE_PROXY=true;        shift   ;;
    --english)        ENGLISH=true;              shift   ;;
    *) if [[ "$_ENGLISH_PRESCAN" == true ]]; then warn "Unknown parameter: $1"; else warn "Unbekannter Parameter: $1"; fi; shift ;;
  esac
done

# ─── Sprachauswahl / Language selection ──────────────────────────────────────
if [[ "$ENGLISH" == false ]]; then
  echo -e "\n${BOLD}Sprache / Language:${RESET}"
  echo -e "  1) Deutsch  ${CYAN}[Standard / Default]${RESET}"
  echo -e "  2) English"
  read -rp "$(echo -e "${BOLD}Auswahl / Choice [1/2]:${RESET} ")" _lang_ui
  [[ "${_lang_ui}" == "2" ]] && ENGLISH=true
fi

# WordPress-Sprache entsprechend der UI-Sprache setzen (sofern nicht per --lang übergeben)
if [[ -z "$WP_LANG" ]]; then
  [[ "$ENGLISH" == true ]] && WP_LANG="en_US" || WP_LANG="de_DE"
fi

# ─── Language strings ─────────────────────────────────────────────────────────
if [[ "$ENGLISH" == true ]]; then
  L_ROOT_ERR="This script must be run as root. Please use 'sudo bash $0'."
  L_OS_ERR="Unsupported OS. Ubuntu 24.04+ or Debian 13+ required."
  L_OS_DETECTED="Detected OS"
  L_UNKNOWN_PARAM="Unknown parameter"
  L_SECTION_CONFIG="WooCommerce Production Installer — Configuration"
  L_PROMPT_DOMAIN="Domain (e.g. example.com)"
  L_ERR_DOMAIN="Domain cannot be empty."
  L_PROMPT_EMAIL="Admin e-mail"
  L_ERR_EMAIL="E-mail cannot be empty."
  L_PROMPT_TITLE="Site title [My WooCommerce Shop]"
  L_PROMPT_USER="WP admin username [admin]"
  L_PHP_SELECT="Select PHP version"
  L_PHP_STD="default / recommended"
  L_PHP_DEV="development version"
  L_PHP_WARN="PHP 8.5 is a development version — not recommended for production."
  L_PHP_INVALID="Invalid selection, using PHP 8.3."
  L_PROMPT_PHP="Selection [1-5, default: 3]"
  L_MEM_SELECT="Select PHP memory limit"
  L_MEM_SMALL="WooCommerce minimum"
  L_MEM_STD="default / recommended for WooCommerce"
  L_MEM_MED="medium-sized shops"
  L_MEM_LARGE="large / high-traffic shops"
  L_MEM_INVALID="Invalid selection, using 512M."
  L_PROMPT_MEM="Selection [1-4, default: 2]"
  L_PROMPT_LANG="WordPress language [en_US]"
  L_WP_LANG_DEFAULT="en_US"
  L_PROMPT_TZ="Timezone [Europe/Berlin]"
  L_PROMPT_PROXY="Is the site behind a reverse proxy (NPM/Traefik/Cloudflare)? [y/N]"
  L_PROXY_ACTIVE="Reverse proxy mode active — SSL via Certbot will be skipped."
  L_WC_SSL_HINT="WooCommerce requires HTTPS for payment processing — SSL is strongly recommended."
  L_PROMPT_SSL="Set up SSL with Let's Encrypt? [y/N]"
  L_PROMPT_PMA="Install phpMyAdmin? (Subdomain: phpmyadmin.DOMAIN) [y/N]"
  L_PROMPT_FB="Install FileBrowser? (Subdomain: files.DOMAIN) [y/N]"
  L_WC_CURRENCY_SELECT="Select shop currency"
  L_WC_CURRENCY_EUR="Euro (EU)"
  L_WC_CURRENCY_USD="US Dollar"
  L_WC_CURRENCY_GBP="British Pound"
  L_WC_CURRENCY_CHF="Swiss Franc"
  L_WC_CURRENCY_INVALID="Invalid selection, using EUR."
  L_PROMPT_WC_CURRENCY="Selection [1-4, default: 1]"
  L_PROMPT_WC_COUNTRY="Shop base country/state (e.g. DE, AT, CH, US:CA) [DE]"
  L_SUMMARY="Installation parameters"
  L_SUMMARY_DIR="WP directory"
  L_SUMMARY_PHP="PHP version"
  L_SUMMARY_MEM="Memory limit"
  L_SUMMARY_LANG="Language"
  L_SUMMARY_TZ="Timezone"
  L_SUMMARY_PROXY="Reverse proxy"
  L_SUMMARY_WC_CURRENCY="Currency"
  L_SUMMARY_WC_COUNTRY="Country"
  L_PROMPT_CONFIRM="Install now? [y/N]"
  L_ABORTED="Aborted."
  L_CREDS_SAVED="Credentials saved"
  L_SYSTEM_OK="System updated."
  L_NGINX_REALIP="Nginx Real-IP module configured (real client IPs via X-Forwarded-For)."
  L_NGINX_OK="Nginx configured with FastCGI cache."
  L_MARIADB_CLEAN="Previous MariaDB installation detected — cleaning up..."
  L_MARIADB_CLEANED="MariaDB cleaned."
  L_REDIS_OK="Redis configured (127.0.0.1:6379, maxmemory=256mb, LRU)."
  L_UFW_OK="UFW enabled: SSH, HTTP, HTTPS allowed."
  L_F2B_OK="Fail2ban with WordPress, WooCommerce and Nginx jails activated."
  L_F2B_WHITELIST="Fail2ban: Private networks (10.x, 172.16.x, 192.168.x) always whitelisted."
  L_WP_OK="WordPress downloaded and configured."
  L_URLS_HTTPS="WordPress URLs set to https."
  L_NGINX_HELPER_OK="Nginx Helper installed and configured — please activate it manually in WP Admin > Plugins."
  L_WPCLI_OK="WP-CLI installed and WordPress configured."
  L_SECTION_WC="9/10 — WooCommerce"
  L_WC_OK="WooCommerce installed and configured."
  L_WC_PAGES="WooCommerce default pages created (Shop, Cart, Checkout, My Account)."
  L_BACKUPS_OK="Automatic DB backups configured (/root/backups/mysql, 7-day rotation)."
  L_SSL_OK="SSL certificate set up. HTTPS active."
  L_SSL_WARN="Certbot failed — a reverse proxy (NPM/Cloudflare) may be in front of this server."
  L_SSL_WARN2="SSL is managed by the reverse proxy. Certbot not needed on the WordPress server."
  L_SSL_SKIP="SSL skipped. Set up manually: certbot --nginx -d"
  L_SWAP_CREATE="RAM: %sMB — creating %s swap..."
  L_SWAP_OK="Swap created and activated."
  L_SWAP_EXISTS="Swap already present (%sMB) — skipping."
  L_SECTION_1="1/10 — System Update"
  L_SECTION_2="2/10 — Nginx + FastCGI Cache"
  L_SECTION_4="4/10 — MariaDB"
  L_SECTION_5="5/10 — Redis Object Cache"
  L_SECTION_6="6/10 — UFW Firewall + Fail2ban"
  L_SECTION_7="7/10 — Install WordPress"
  L_SECTION_8="8/10 — WP-CLI"
  L_SECTION_9="10/10 — Log Rotation, Cron & Final Optimizations"
else
  L_ROOT_ERR="Dieses Script muss als root ausgeführt werden. Bitte 'sudo bash $0' verwenden."
  L_OS_ERR="Nicht unterstütztes OS. Ubuntu 24.04+ oder Debian 13+ erforderlich."
  L_OS_DETECTED="Erkanntes Betriebssystem"
  L_UNKNOWN_PARAM="Unbekannter Parameter"
  L_SECTION_CONFIG="WooCommerce Production Installer — Konfiguration"
  L_PROMPT_DOMAIN="Domain (z.B. example.com)"
  L_ERR_DOMAIN="Domain darf nicht leer sein."
  L_PROMPT_EMAIL="Admin E-Mail"
  L_ERR_EMAIL="E-Mail darf nicht leer sein."
  L_PROMPT_TITLE="Site-Titel [My WooCommerce Shop]"
  L_PROMPT_USER="WP Admin-Benutzername [admin]"
  L_PHP_SELECT="PHP-Version auswählen"
  L_PHP_STD="Standard / empfohlen"
  L_PHP_DEV="Entwicklungsversion"
  L_PHP_WARN="PHP 8.5 ist eine Entwicklungsversion — nicht für Produktion empfohlen."
  L_PHP_INVALID="Ungültige Auswahl, verwende PHP 8.3."
  L_PROMPT_PHP="Auswahl [1-5, Standard: 3]"
  L_MEM_SELECT="PHP Memory Limit auswählen"
  L_MEM_SMALL="WooCommerce Minimum"
  L_MEM_STD="Standard / für WooCommerce empfohlen"
  L_MEM_MED="mittelgroße Shops"
  L_MEM_LARGE="große / hochfrequentierte Shops"
  L_MEM_INVALID="Ungültige Auswahl, verwende 512M."
  L_PROMPT_MEM="Auswahl [1-4, Standard: 2]"
  L_PROMPT_LANG="WordPress-Sprache [de_DE]"
  L_WP_LANG_DEFAULT="de_DE"
  L_PROMPT_TZ="Zeitzone [Europe/Berlin]"
  L_PROMPT_PROXY="Läuft die Site hinter einem Reverse Proxy (NPM/Traefik/Cloudflare)? [j/N]"
  L_PROXY_ACTIVE="Reverse Proxy Modus aktiv — SSL via Certbot wird übersprungen."
  L_WC_SSL_HINT="WooCommerce benötigt HTTPS für Zahlungsabwicklung — SSL wird dringend empfohlen."
  L_PROMPT_SSL="SSL mit Let's Encrypt einrichten? [j/N]"
  L_PROMPT_PMA="phpMyAdmin installieren? (Subdomain: phpmyadmin.DOMAIN) [j/N]"
  L_PROMPT_FB="FileBrowser installieren? (Subdomain: files.DOMAIN) [j/N]"
  L_WC_CURRENCY_SELECT="Shop-Währung auswählen"
  L_WC_CURRENCY_EUR="Euro (EU)"
  L_WC_CURRENCY_USD="US Dollar"
  L_WC_CURRENCY_GBP="Britisches Pfund"
  L_WC_CURRENCY_CHF="Schweizer Franken"
  L_WC_CURRENCY_INVALID="Ungültige Auswahl, verwende EUR."
  L_PROMPT_WC_CURRENCY="Auswahl [1-4, Standard: 1]"
  L_PROMPT_WC_COUNTRY="Shop-Basisland/-staat (z.B. DE, AT, CH, US:CA) [DE]"
  L_SUMMARY="Installationsparameter"
  L_SUMMARY_DIR="WP-Verzeichnis"
  L_SUMMARY_PHP="PHP-Version"
  L_SUMMARY_MEM="Memory Limit"
  L_SUMMARY_LANG="Sprache"
  L_SUMMARY_TZ="Zeitzone"
  L_SUMMARY_PROXY="Reverse Proxy"
  L_SUMMARY_WC_CURRENCY="Währung"
  L_SUMMARY_WC_COUNTRY="Land"
  L_PROMPT_CONFIRM="Jetzt installieren? [j/N]"
  L_ABORTED="Abgebrochen."
  L_CREDS_SAVED="Zugangsdaten gespeichert"
  L_SYSTEM_OK="System aktualisiert."
  L_NGINX_REALIP="Nginx Real-IP Modul konfiguriert (echte Client-IPs via X-Forwarded-For)."
  L_NGINX_OK="Nginx konfiguriert mit FastCGI Cache."
  L_MARIADB_CLEAN="Vorherige MariaDB-Installation erkannt — bereinige für Neuinstallation..."
  L_MARIADB_CLEANED="MariaDB bereinigt."
  L_REDIS_OK="Redis konfiguriert (127.0.0.1:6379, maxmemory=256mb, LRU)."
  L_UFW_OK="UFW aktiviert: SSH, HTTP, HTTPS erlaubt."
  L_F2B_OK="Fail2ban mit WordPress-, WooCommerce- und Nginx-Jails aktiviert."
  L_F2B_WHITELIST="Fail2ban: Private Netzwerke (10.x, 172.16.x, 192.168.x) immer auf Whitelist."
  L_WP_OK="WordPress heruntergeladen und konfiguriert."
  L_URLS_HTTPS="WordPress URLs auf https gesetzt."
  L_NGINX_HELPER_OK="Nginx Helper installiert und konfiguriert — bitte manuell aktivieren unter WP Admin > Plugins."
  L_WPCLI_OK="WP-CLI installiert und WordPress konfiguriert."
  L_SECTION_WC="9/10 — WooCommerce"
  L_WC_OK="WooCommerce installiert und konfiguriert."
  L_WC_PAGES="WooCommerce Standard-Seiten erstellt (Shop, Warenkorb, Kasse, Mein Konto)."
  L_BACKUPS_OK="Automatische DB-Backups konfiguriert (/root/backups/mysql, 7 Tage Rotation)."
  L_SSL_OK="SSL-Zertifikat eingerichtet. HTTPS aktiv."
  L_SSL_WARN="Certbot fehlgeschlagen — möglicherweise läuft ein Reverse Proxy (NPM/Cloudflare) vor diesem Server."
  L_SSL_WARN2="SSL wird in diesem Fall vom Reverse Proxy verwaltet. Certbot auf dem WordPress-Server nicht notwendig."
  L_SSL_SKIP="SSL übersprungen. Manuell einrichten: certbot --nginx -d"
  L_SWAP_CREATE="RAM: %sMB — lege %s Swap an..."
  L_SWAP_OK="Swap angelegt und aktiviert."
  L_SWAP_EXISTS="Swap bereits vorhanden (%sMB) — überspringe."
  L_SECTION_1="1/10 — System Update"
  L_SECTION_2="2/10 — Nginx + FastCGI Cache"
  L_SECTION_4="4/10 — MariaDB"
  L_SECTION_5="5/10 — Redis Object Cache"
  L_SECTION_6="6/10 — UFW Firewall + Fail2ban"
  L_SECTION_7="7/10 — WordPress installieren"
  L_SECTION_8="8/10 — WP-CLI"
  L_SECTION_9="10/10 — Logrotation, Cron & finale Optimierungen"
fi

# ─── Interactive prompts (if not provided via args) ────────────────────────────
section "$L_SECTION_CONFIG"

if [[ -z "$WP_DOMAIN" ]]; then
  read -rp "$(echo -e "${BOLD}${L_PROMPT_DOMAIN}:${RESET} ")" WP_DOMAIN
fi
[[ -z "$WP_DOMAIN" ]] && error "$L_ERR_DOMAIN"

if [[ -z "$WP_ADMIN_EMAIL" ]]; then
  read -rp "$(echo -e "${BOLD}${L_PROMPT_EMAIL}:${RESET} ")" WP_ADMIN_EMAIL
fi
[[ -z "$WP_ADMIN_EMAIL" ]] && error "$L_ERR_EMAIL"

read -rp "$(echo -e "${BOLD}${L_PROMPT_TITLE}:${RESET} ")" _title
WP_SITE_TITLE="${_title:-$WP_SITE_TITLE}"

read -rp "$(echo -e "${BOLD}${L_PROMPT_USER}:${RESET} ")" _user
WP_ADMIN_USER="${_user:-$WP_ADMIN_USER}"

# ─── PHP version selection ────────────────────────────────────────────────────
if [[ "$PHP_VERSION" == "8.3" ]]; then
  echo -e "\n${BOLD}${L_PHP_SELECT}:${RESET}"
  echo -e "  1) PHP 8.1"
  echo -e "  2) PHP 8.2"
  echo -e "  3) PHP 8.3  ${CYAN}[${L_PHP_STD}]${RESET}"
  echo -e "  4) PHP 8.4"
  echo -e "  5) PHP 8.5  ${YELLOW}(${L_PHP_DEV})${RESET}"
  read -rp "$(echo -e "${BOLD}${L_PROMPT_PHP}:${RESET} ")" _php_choice
  case "${_php_choice:-3}" in
    1) PHP_VERSION="8.1" ;;
    2) PHP_VERSION="8.2" ;;
    3) PHP_VERSION="8.3" ;;
    4) PHP_VERSION="8.4" ;;
    5) PHP_VERSION="8.5" ; warn "$L_PHP_WARN" ;;
    *) warn "$L_PHP_INVALID"; PHP_VERSION="8.3" ;;
  esac
fi

# ─── PHP memory limit selection ───────────────────────────────────────────────
if [[ "$PHP_MEMORY_LIMIT" == "512M" ]]; then
  echo -e "\n${BOLD}${L_MEM_SELECT}:${RESET}"
  echo -e "  1) 256M   ${CYAN}(${L_MEM_SMALL})${RESET}"
  echo -e "  2) 512M   ${CYAN}[${L_MEM_STD}]${RESET}"
  echo -e "  3) 768M   ${CYAN}(${L_MEM_MED})${RESET}"
  echo -e "  4) 1024M  ${CYAN}(${L_MEM_LARGE})${RESET}"
  read -rp "$(echo -e "${BOLD}${L_PROMPT_MEM}:${RESET} ")" _mem_choice
  case "${_mem_choice:-2}" in
    1) PHP_MEMORY_LIMIT="256M"  ;;
    2) PHP_MEMORY_LIMIT="512M"  ;;
    3) PHP_MEMORY_LIMIT="768M"  ;;
    4) PHP_MEMORY_LIMIT="1024M" ;;
    *) warn "$L_MEM_INVALID"; PHP_MEMORY_LIMIT="512M" ;;
  esac
fi

# ─── Language & timezone ─────────────────────────────────────────────────────
if [[ "$WP_LANG" == "$L_WP_LANG_DEFAULT" ]]; then
  read -rp "$(echo -e "${BOLD}${L_PROMPT_LANG}:${RESET} ")" _lang
  WP_LANG="${_lang:-$L_WP_LANG_DEFAULT}"
fi
if [[ "$WP_TIMEZONE" == "Europe/Berlin" ]]; then
  read -rp "$(echo -e "${BOLD}${L_PROMPT_TZ}:${RESET} ")" _tz
  WP_TIMEZONE="${_tz:-Europe/Berlin}"
fi

# ─── Reverse proxy? ───────────────────────────────────────────────────────────
if [[ "$REVERSE_PROXY" == false ]]; then
  read -rp "$(echo -e "${BOLD}${L_PROMPT_PROXY}${RESET} ")" _rp
  [[ "${_rp,,}" == "j" || "${_rp,,}" == "y" ]] && REVERSE_PROXY=true
fi
if [[ "$REVERSE_PROXY" == true ]]; then
  info "$L_PROXY_ACTIVE"
  INSTALL_SSL=false
fi

# ─── SSL with Let's Encrypt? ─────────────────────────────────────────────────
if [[ "$INSTALL_SSL" == false && "$REVERSE_PROXY" == false ]]; then
  info "$L_WC_SSL_HINT"
  read -rp "$(echo -e "${BOLD}${L_PROMPT_SSL}${RESET} ")" _ssl
  [[ "${_ssl,,}" == "j" || "${_ssl,,}" == "y" ]] && INSTALL_SSL=true
fi

# ─── phpMyAdmin? ─────────────────────────────────────────────────────────────
if [[ "$INSTALL_PHPMYADMIN" == false ]]; then
  read -rp "$(echo -e "${BOLD}${L_PROMPT_PMA/DOMAIN/$WP_DOMAIN}${RESET} ")" _pma
  [[ "${_pma,,}" == "j" || "${_pma,,}" == "y" ]] && INSTALL_PHPMYADMIN=true
fi

# ─── FileBrowser? ────────────────────────────────────────────────────────────
if [[ "$INSTALL_FILEBROWSER" == false ]]; then
  read -rp "$(echo -e "${BOLD}${L_PROMPT_FB/DOMAIN/$WP_DOMAIN}${RESET} ")" _fb
  [[ "${_fb,,}" == "j" || "${_fb,,}" == "y" ]] && INSTALL_FILEBROWSER=true
fi

# ─── WooCommerce currency selection ──────────────────────────────────────────
if [[ "$WC_CURRENCY" == "EUR" ]]; then
  echo -e "\n${BOLD}${L_WC_CURRENCY_SELECT}:${RESET}"
  echo -e "  1) EUR  ${CYAN}[${L_WC_CURRENCY_EUR}]${RESET}"
  echo -e "  2) USD  ${CYAN}(${L_WC_CURRENCY_USD})${RESET}"
  echo -e "  3) GBP  ${CYAN}(${L_WC_CURRENCY_GBP})${RESET}"
  echo -e "  4) CHF  ${CYAN}(${L_WC_CURRENCY_CHF})${RESET}"
  read -rp "$(echo -e "${BOLD}${L_PROMPT_WC_CURRENCY}:${RESET} ")" _wc_currency
  case "${_wc_currency:-1}" in
    1) WC_CURRENCY="EUR" ;;
    2) WC_CURRENCY="USD" ;;
    3) WC_CURRENCY="GBP" ;;
    4) WC_CURRENCY="CHF" ;;
    *) warn "$L_WC_CURRENCY_INVALID"; WC_CURRENCY="EUR" ;;
  esac
fi

# ─── WooCommerce base country ─────────────────────────────────────────────────
read -rp "$(echo -e "${BOLD}${L_PROMPT_WC_COUNTRY}:${RESET} ")" _wc_country
WC_COUNTRY="${_wc_country:-DE}"
# Force uppercase
WC_COUNTRY="${WC_COUNTRY^^}"

# ─── Generate random secrets ──────────────────────────────────────────────────
DB_NAME="wp_$(tr -dc 'a-z0-9' </dev/urandom | head -c 8 || true)"
DB_USER="wpuser_$(tr -dc 'a-z0-9' </dev/urandom | head -c 6 || true)"
DB_PASS="$(tr -dc 'A-Za-z0-9!@#$%^&*' </dev/urandom | head -c 32 || true)"
# DB_ROOT_PASS nicht mehr benötigt — MariaDB root nutzt unix_socket Auth
WP_ADMIN_PASS="$(tr -dc 'A-Za-z0-9!@#$%' </dev/urandom | head -c 24 || true)"
REDIS_PASS="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32 || true)"
PMA_DB_USER="pma_$(tr -dc 'a-z0-9' </dev/urandom | head -c 6 || true)"
PMA_DB_PASS="$(tr -dc 'A-Za-z0-9!@#$%' </dev/urandom | head -c 32 || true)"
PMA_BLOWFISH="$(tr -dc 'A-Za-z0-9!@#$%^&*()_+' </dev/urandom | head -c 32 || true)"
PMA_HTPASSWD_PASS="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16 || true)"
FB_PASS="$(tr -dc 'A-Za-z0-9!@#$%' </dev/urandom | head -c 24 || true)"
FB_HTPASSWD_PASS="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16 || true)"

# ─── Summary ──────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}${L_SUMMARY}:${RESET}"
echo -e "  Domain        : ${CYAN}${WP_DOMAIN}${RESET}"
echo -e "  ${L_SUMMARY_DIR}: ${CYAN}${WP_DIR}${RESET}"
echo -e "  ${L_SUMMARY_PHP}   : ${CYAN}${PHP_VERSION}${RESET}"
echo -e "  ${L_SUMMARY_MEM}  : ${CYAN}${PHP_MEMORY_LIMIT}${RESET}"
echo -e "  ${L_SUMMARY_LANG}       : ${CYAN}${WP_LANG}${RESET}"
echo -e "  ${L_SUMMARY_TZ}      : ${CYAN}${WP_TIMEZONE}${RESET}"
echo -e "  SSL           : ${CYAN}${INSTALL_SSL}${RESET}"
echo -e "  ${L_SUMMARY_PROXY} : ${CYAN}${REVERSE_PROXY}${RESET}"
echo -e "  WooCommerce   : ${CYAN}true${RESET}"
echo -e "  ${L_SUMMARY_WC_CURRENCY}      : ${CYAN}${WC_CURRENCY}${RESET}"
echo -e "  ${L_SUMMARY_WC_COUNTRY}          : ${CYAN}${WC_COUNTRY}${RESET}"
echo -e "  phpMyAdmin    : ${CYAN}${INSTALL_PHPMYADMIN}${RESET}"
echo -e "  FileBrowser   : ${CYAN}${INSTALL_FILEBROWSER}${RESET}"
echo -e "  DB Name       : ${CYAN}${DB_NAME}${RESET}"
echo -e "  DB User       : ${CYAN}${DB_USER}${RESET}"
echo ""
read -rp "$(echo -e "${BOLD}${L_PROMPT_CONFIRM}${RESET} ")" CONFIRM
[[ "${CONFIRM,,}" != "j" && "${CONFIRM,,}" != "y" ]] && echo "$L_ABORTED" && exit 0

# ─── Credentials speichern ────────────────────────────────────────────────────
CREDS_FILE="/root/.wp_install_credentials_${WP_DOMAIN}.txt"
cat > "$CREDS_FILE" <<EOF
# WooCommerce Installation Credentials — $(date)
# BITTE SICHER AUFBEWAHREN!
Domain:          https://${WP_DOMAIN}
WP Admin User:   ${WP_ADMIN_USER}
WP Admin Pass:   ${WP_ADMIN_PASS}
WP Admin Email:  ${WP_ADMIN_EMAIL}
DB Name:         ${DB_NAME}
DB User:         ${DB_USER}
DB Password:     ${DB_PASS}
DB Root Access:  unix_socket (sudo mysql -uroot)
Redis Password:  ${REDIS_PASS}
─────────────────────────────────────
WooCommerce Admin:   https://${WP_DOMAIN}/wp-admin/admin.php?page=wc-admin
Shop URL:            https://${WP_DOMAIN}/shop
Währung / Currency:  ${WC_CURRENCY}
Basisland / Country: ${WC_COUNTRY}
EOF

if [[ "$INSTALL_PHPMYADMIN" == true ]]; then
cat >> "$CREDS_FILE" <<EOF
─────────────────────────────────────
phpMyAdmin URL:     http://phpmyadmin.${WP_DOMAIN}
phpMyAdmin Login:   ${WP_ADMIN_USER} / ${PMA_HTPASSWD_PASS}  (HTTP Basic Auth)
PMA DB User:        ${PMA_DB_USER}
PMA DB Password:    ${PMA_DB_PASS}
EOF
fi

if [[ "$INSTALL_FILEBROWSER" == true ]]; then
cat >> "$CREDS_FILE" <<EOF
─────────────────────────────────────
FileBrowser URL:    http://files.${WP_DOMAIN}
FileBrowser Login:  ${WP_ADMIN_USER} / ${FB_HTPASSWD_PASS}  (HTTP Basic Auth)
FileBrowser User:   ${WP_ADMIN_USER}
FileBrowser Pass:   ${FB_PASS}
EOF
fi
chmod 600 "$CREDS_FILE"
info "$L_CREDS_SAVED: $CREDS_FILE"

# =============================================================================
# 1. SYSTEM UPDATE
# =============================================================================
section "$L_SECTION_1"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq \
  curl wget gnupg2 lsb-release ca-certificates \
  unzip zip git htop ncdu tree net-tools
# software-properties-common nur auf Ubuntu nötig (für add-apt-repository)
if [[ "$OS_TYPE" == "ubuntu" ]]; then
  apt-get install -y -qq software-properties-common
fi
success "$L_SYSTEM_OK"

# ─── Swap-Datei anlegen (dynamisch je nach RAM) ──────────────────────────────
SWAP_TOTAL=$(free -m | awk '/^Swap:/{print $2}')
TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
if [[ "$SWAP_TOTAL" -lt 512 ]]; then
  if   [[ "$TOTAL_RAM" -lt 1024 ]]; then SWAP_SIZE="2G"; SWAP_MB=2048
  elif [[ "$TOTAL_RAM" -lt 2048 ]]; then SWAP_SIZE="1G"; SWAP_MB=1024
  else                                    SWAP_SIZE="512M"; SWAP_MB=512
  fi
  info "$(printf "$L_SWAP_CREATE" "$TOTAL_RAM" "$SWAP_SIZE")"
  fallocate -l "$SWAP_SIZE" /swapfile 2>/dev/null \
    || dd if=/dev/zero of=/swapfile bs=1M count="${SWAP_MB}" status=none
  chmod 600 /swapfile
  mkswap /swapfile -q
  swapon /swapfile
  grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  sysctl -w vm.swappiness=10 >/dev/null
  grep -q 'vm.swappiness' /etc/sysctl.conf \
    || echo 'vm.swappiness=10' >> /etc/sysctl.conf
  success "$L_SWAP_OK"
else
  info "$(printf "$L_SWAP_EXISTS" "$SWAP_TOTAL")"
fi

# =============================================================================
# 2. NGINX + FastCGI Cache
# =============================================================================
section "$L_SECTION_2"
apt-get install -y -qq nginx libnginx-mod-http-cache-purge \
  libnginx-mod-http-brotli-filter libnginx-mod-http-brotli-static
systemctl enable nginx

# FastCGI Cache Verzeichnis
mkdir -p "$NGINX_FASTCGI_CACHE_DIR"
chown -R www-data:www-data /var/cache/nginx

# Nginx globale Optimierungen
cat > /etc/nginx/nginx.conf <<'NGINXCONF'
user www-data;
worker_processes auto;
worker_rlimit_nofile 65535;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections  4096;
    multi_accept        on;
    use                 epoll;
}

http {
    # Basic
    sendfile            on;
    tcp_nopush          on;
    tcp_nodelay         on;
    keepalive_timeout   65;
    keepalive_requests  1000;
    types_hash_max_size 2048;
    server_tokens       off;

    include             /etc/nginx/mime.types;
    default_type        application/octet-stream;

    # Logging
    log_format main '$remote_addr - $remote_user [$time_local] '
                    '"$request" $status $body_bytes_sent '
                    '"$http_referer" "$http_user_agent" '
                    'rt=$request_time uc="$upstream_cache_status"';
    access_log /var/log/nginx/access.log main buffer=16k flush=2m;
    error_log  /var/log/nginx/error.log warn;

    # GZIP
    gzip              on;
    gzip_vary         on;
    gzip_proxied      any;
    gzip_comp_level   5;
    gzip_min_length   256;
    gzip_types
        text/plain text/css text/xml text/javascript
        application/javascript application/x-javascript
        application/json application/xml application/rss+xml
        application/atom+xml image/svg+xml font/opentype
        application/vnd.ms-fontobject application/x-font-ttf;

    # Brotli (bessere Komprimierung als gzip, ~15-25% effizienter)
    brotli              on;
    brotli_comp_level   6;
    brotli_min_length   256;
    brotli_types
        text/plain text/css text/xml text/javascript
        application/javascript application/x-javascript
        application/json application/xml application/rss+xml
        application/atom+xml image/svg+xml font/opentype
        application/vnd.ms-fontobject application/x-font-ttf;

    # FastCGI Cache Zone
    fastcgi_cache_path /var/cache/nginx/fastcgi
        levels=1:2
        keys_zone=WORDPRESS:100m
        inactive=60m
        max_size=1g
        use_temp_path=off;
    fastcgi_cache_key "$scheme$request_method$host$request_uri";

    # Timeouts
    client_body_timeout   12;
    client_header_timeout 12;
    send_timeout          10;
    client_max_body_size  64m;

    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
NGINXCONF

# Nginx FastCGI Params Snippet
cat > /etc/nginx/snippets/fastcgi-params-wp.conf <<'FASTCGI'
fastcgi_param SCRIPT_FILENAME     $document_root$fastcgi_script_name;
fastcgi_param QUERY_STRING        $query_string;
fastcgi_param REQUEST_METHOD      $request_method;
fastcgi_param CONTENT_TYPE        $content_type;
fastcgi_param CONTENT_LENGTH      $content_length;
fastcgi_param SCRIPT_NAME         $fastcgi_script_name;
fastcgi_param REQUEST_URI         $request_uri;
fastcgi_param DOCUMENT_URI        $document_uri;
fastcgi_param DOCUMENT_ROOT       $document_root;
fastcgi_param SERVER_PROTOCOL     $server_protocol;
fastcgi_param GATEWAY_INTERFACE   CGI/1.1;
fastcgi_param SERVER_SOFTWARE     nginx/$nginx_version;
fastcgi_param REMOTE_ADDR         $remote_addr;
fastcgi_param REMOTE_PORT         $remote_port;
fastcgi_param SERVER_ADDR         $server_addr;
fastcgi_param SERVER_PORT         $server_port;
fastcgi_param SERVER_NAME         $server_name;
fastcgi_param HTTPS               $https if_not_empty;
fastcgi_param HTTP_PROXY          "";
FASTCGI

# Security Headers Snippet
cat > /etc/nginx/snippets/security-headers.conf <<'SECHEADERS'
add_header X-Frame-Options           "SAMEORIGIN"           always;
add_header X-XSS-Protection          "1; mode=block"        always;
add_header X-Content-Type-Options    "nosniff"              always;
add_header Referrer-Policy           "strict-origin-when-cross-origin" always;
add_header Permissions-Policy        "camera=(), microphone=(), geolocation=()" always;
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
SECHEADERS

# WooCommerce-optimierter Nginx Vhost
cat > "/etc/nginx/sites-available/${WP_DOMAIN}.conf" <<VHOST
# ─── FastCGI Cache Skip Rules ─────────────────────────────────────────────────
map \$http_cookie \$skip_cache_cookie {
    default 0;
    "~*wordpress_logged_in"           1;
    "~*comment_author"                1;
    "~*woocommerce_items_in_cart"     1;
    "~*woocommerce_cart_hash"         1;
    "~*wp_woocommerce_session_"       1;
    "~*wp-postpass_"                  1;
}

map \$request_method \$skip_cache_method {
    default 0;
    POST    1;
}

map \$query_string \$skip_cache_query {
    default 0;
    "~*.+"  1;
}

# ─── WooCommerce: Transaktionsseiten + AJAX immer bypassen ────────────────────
map \$request_uri \$skip_cache_uri_wc {
    default 0;
    "~^/cart"              1;
    "~^/checkout"          1;
    "~^/my-account"        1;
    "~^/wp-json/wc/"       1;
    "~*[?&]wc-ajax="       1;
    "~*[?&]add-to-cart="   1;
}

upstream php${PHP_VERSION}-fpm {
    server unix:/run/php/php${PHP_VERSION}-fpm.sock;
    keepalive 32;
}

server {
    listen 80;
    listen [::]:80;
    server_name ${WP_DOMAIN} www.${WP_DOMAIN};

    # Redirect to HTTPS (nach Certbot-Einrichtung aktivieren)
    # return 301 https://\$host\$request_uri;

    root ${WP_DIR};
    index index.php index.html;

    # Logging
    access_log /var/log/nginx/${WP_DOMAIN}-access.log main;
    error_log  /var/log/nginx/${WP_DOMAIN}-error.log warn;

    include /etc/nginx/snippets/security-headers.conf;

    # ─── FastCGI Cache Status Header ──────────────────────────────────────────
    add_header X-Cache-Status \$upstream_cache_status always;
    add_header X-Cache-Enabled "true" always;

    # ─── Cache bypass logic ───────────────────────────────────────────────────
    set \$skip_cache 0;
    if (\$skip_cache_cookie)   { set \$skip_cache 1; }
    if (\$skip_cache_method)   { set \$skip_cache 1; }
    if (\$skip_cache_query)    { set \$skip_cache 1; }
    if (\$skip_cache_uri_wc)   { set \$skip_cache 1; }
    if (\$request_uri ~* "(/wp-admin/|/xmlrpc.php|/wp-login.php|wp-.*.php|/feed/|index.php|sitemap.xml)") {
        set \$skip_cache 1;
    }

    # ─── WordPress Permalink ──────────────────────────────────────────────────
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    # ─── PHP-FPM + FastCGI Cache ──────────────────────────────────────────────
    location ~ \.php$ {
        try_files \$uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;

        fastcgi_pass   php${PHP_VERSION}-fpm;
        fastcgi_index  index.php;
        fastcgi_read_timeout 300;
        fastcgi_buffers 16 16k;
        fastcgi_buffer_size 32k;

        include /etc/nginx/snippets/fastcgi-params-wp.conf;

        # FastCGI Cache
        fastcgi_cache            WORDPRESS;
        fastcgi_cache_valid       200 301 302 1h;
        fastcgi_cache_valid       404 1m;
        fastcgi_cache_use_stale  error timeout updating http_500 http_503;
        fastcgi_cache_lock       on;
        fastcgi_cache_bypass     \$skip_cache;
        fastcgi_no_cache         \$skip_cache;
        fastcgi_cache_background_update on;
        fastcgi_cache_min_uses   1;
    }

    # ─── Static Assets ────────────────────────────────────────────────────────
    location ~* \.(css|js|ico|gif|jpe?g|png|webp|avif|svg|woff2?|ttf|eot|otf)$ {
        expires     max;
        access_log  off;
        log_not_found off;
        add_header  Cache-Control "public, immutable";
        add_header  Vary "Accept-Encoding";
    }

    # ─── Security: Block access to sensitive files ─────────────────────────────
    location ~ /\.ht        { deny all; }
    location ~ /\.git       { deny all; }
    location = /xmlrpc.php  { deny all; }
    location ~* /(?:uploads|files)/.*\.php$ { deny all; }
    location = /wp-config.php { deny all; }

    # ─── WooCommerce: Privaten Upload-Ordner sperren ─────────────────────────
    location ~* /uploads/woocommerce_uploads/ { deny all; }
    location ~* /uploads/wc-logs/             { deny all; }

    # ─── Limit login page ─────────────────────────────────────────────────────
    location = /wp-login.php {
        limit_req zone=wplogin burst=3 nodelay;
        fastcgi_pass   php${PHP_VERSION}-fpm;
        fastcgi_index  index.php;
        include /etc/nginx/snippets/fastcgi-params-wp.conf;
    }

    # ─── Nginx Helper — FastCGI Cache Purge Endpoint ──────────────────────────
    location ~ /purge(/.*) {
        allow 127.0.0.1;
        deny  all;
        fastcgi_cache_purge WORDPRESS "\$scheme\$request_method\$host\$1";
    }
}

# ─── HTTPS Server Block (nach SSL-Einrichtung via Certbot aktiv) ──────────────
# server {
#     listen 443 ssl http2;
#     listen [::]:443 ssl http2;
#     server_name ${WP_DOMAIN} www.${WP_DOMAIN};
#
#     ssl_certificate     /etc/letsencrypt/live/${WP_DOMAIN}/fullchain.pem;
#     ssl_certificate_key /etc/letsencrypt/live/${WP_DOMAIN}/privkey.pem;
#     ssl_protocols       TLSv1.2 TLSv1.3;
#     ssl_ciphers         ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
#     ssl_prefer_server_ciphers off;
#     ssl_session_cache   shared:SSL:10m;
#     ssl_session_timeout 1d;
#     ssl_stapling        on;
#     ssl_stapling_verify on;
#
#     root ${WP_DIR};
#     index index.php index.html;
#     # ... (gleiche location-Blöcke wie oben)
# }
VHOST

# Rate limiting Zone (private Netzwerke ausgenommen — z.B. NPM als Reverse Proxy)
cat > /etc/nginx/conf.d/rate-limiting.conf <<'RATELIMIT'
geo $limit_key {
    default          $binary_remote_addr;
    127.0.0.1        "";
    10.0.0.0/8       "";
    172.16.0.0/12    "";
    192.168.0.0/16   "";
}
limit_req_zone $limit_key zone=wplogin:10m rate=2r/m;
RATELIMIT

# Real-IP Modul bei Reverse Proxy (echte Client-IPs aus X-Forwarded-For lesen)
if [[ "$REVERSE_PROXY" == true ]]; then
  cat > /etc/nginx/conf.d/real-ip.conf <<'REALIP'
set_real_ip_from 10.0.0.0/8;
set_real_ip_from 172.16.0.0/12;
set_real_ip_from 192.168.0.0/16;
set_real_ip_from 127.0.0.1;
real_ip_header X-Forwarded-For;
real_ip_recursive on;
REALIP
  info "$L_NGINX_REALIP"
fi

# Default site deaktivieren, WordPress aktivieren
rm -f /etc/nginx/sites-enabled/default
ln -sf "/etc/nginx/sites-available/${WP_DOMAIN}.conf" "/etc/nginx/sites-enabled/${WP_DOMAIN}.conf"

nginx -t && systemctl reload nginx
success "$L_NGINX_OK"

# =============================================================================
# 3. PHP-FPM + OPcache
# =============================================================================
section "3/10 — PHP ${PHP_VERSION}-FPM + OPcache"
if [[ "$OS_TYPE" == "ubuntu" ]]; then
  add-apt-repository -y ppa:ondrej/php >/dev/null 2>&1
else
  # Debian: packages.sury.org (ondrej's offizielles Debian-Repo)
  rm -f /etc/apt/trusted.gpg.d/sury-php.gpg
  curl -fsSL https://packages.sury.org/php/apt.gpg \
    | gpg --dearmor -o /etc/apt/trusted.gpg.d/sury-php.gpg
  echo "deb https://packages.sury.org/php/ $(lsb_release -cs) main" \
    > /etc/apt/sources.list.d/sury-php.list
fi
apt-get update -qq
apt-get install -y -qq \
  "php${PHP_VERSION}-fpm" \
  "php${PHP_VERSION}-mysql" \
  "php${PHP_VERSION}-redis" \
  "php${PHP_VERSION}-curl" \
  "php${PHP_VERSION}-gd" \
  "php${PHP_VERSION}-mbstring" \
  "php${PHP_VERSION}-xml" \
  "php${PHP_VERSION}-xmlrpc" \
  "php${PHP_VERSION}-soap" \
  "php${PHP_VERSION}-intl" \
  "php${PHP_VERSION}-zip" \
  "php${PHP_VERSION}-bcmath" \
  "php${PHP_VERSION}-imagick" \
  "php${PHP_VERSION}-cli"

# php-opcache ist in PHP 8.5+ bereits in php-common enthalten — nur installieren wenn verfügbar
if apt-cache show "php${PHP_VERSION}-opcache" &>/dev/null 2>&1; then
  apt-get install -y -qq "php${PHP_VERSION}-opcache"
fi

# Standard www.conf Pool entfernen — verhindert Socket-Konflikt mit wordpress.conf
rm -f "/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf"

# PHP-FPM Pool Optimierung (WooCommerce-optimiert)
cat > "/etc/php/${PHP_VERSION}/fpm/pool.d/wordpress.conf" <<PHPPOOL
[wordpress]
user  = www-data
group = www-data

listen = /run/php/php${PHP_VERSION}-fpm.sock
listen.owner = www-data
listen.group = www-data
listen.mode  = 0660

; Prozess-Manager: dynamisch
pm                   = dynamic
pm.max_children      = 50
pm.start_servers     = 5
pm.min_spare_servers = 5
pm.max_spare_servers = 35
pm.max_requests      = 500
pm.process_idle_timeout = 10s

; Request-Timeouts
request_terminate_timeout = 300s
request_slowlog_timeout   = 5s
slowlog                   = /var/log/php${PHP_VERSION}-fpm-slow.log

; Sicherheit
security.limit_extensions = .php

; Environment
env[HOSTNAME]  = \$HOSTNAME
env[PATH]      = /usr/local/bin:/usr/bin:/bin
env[TMP]       = /tmp
env[TMPDIR]    = /tmp
env[TEMP]      = /tmp

; PHP Einstellungen (WooCommerce-optimiert)
php_admin_value[error_log]         = /var/log/php${PHP_VERSION}-fpm-error.log
php_admin_flag[log_errors]         = on
php_value[upload_max_filesize]     = 64M
php_value[post_max_size]           = 64M
php_value[memory_limit]            = ${PHP_MEMORY_LIMIT}
php_value[max_execution_time]      = 300
php_value[max_input_vars]          = 10000
php_value[max_input_time]          = 300
php_value[session.gc_maxlifetime]  = 1440
PHPPOOL

# PHP.ini Optimierungen
PHP_INI="/etc/php/${PHP_VERSION}/fpm/php.ini"
sed -i "s|^;date.timezone.*|date.timezone = ${WP_TIMEZONE}|"  "$PHP_INI"
sed -i 's/^upload_max_filesize.*/upload_max_filesize = 64M/'  "$PHP_INI"
sed -i 's/^post_max_size.*/post_max_size = 64M/'              "$PHP_INI"
sed -i "s/^memory_limit.*/memory_limit = ${PHP_MEMORY_LIMIT}/"  "$PHP_INI"
sed -i 's/^max_execution_time.*/max_execution_time = 300/'    "$PHP_INI"
sed -i 's/^max_input_time.*/max_input_time = 300/'            "$PHP_INI"
sed -i 's/^;max_input_vars.*/max_input_vars = 10000/'         "$PHP_INI"
sed -i 's/^expose_php.*/expose_php = Off/'                    "$PHP_INI"

# OPcache Tuning (separate Datei — System's opcache.ini bleibt unberührt)
# zend_extension wird bereits vom php-opcache Paket geladen — nicht doppelt laden!
cat > "/etc/php/${PHP_VERSION}/fpm/conf.d/99-opcache-wordpress.ini" <<'OPCACHE'
opcache.enable=1
opcache.enable_cli=0
opcache.memory_consumption=256
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=10000
opcache.max_wasted_percentage=10
opcache.validate_timestamps=0
opcache.revalidate_freq=0
opcache.save_comments=1
opcache.fast_shutdown=1
opcache.jit=tracing
opcache.jit_buffer_size=128M
OPCACHE

# Standard Pool deaktivieren, WordPress Pool aktivieren
systemctl enable "php${PHP_VERSION}-fpm"
systemctl restart "php${PHP_VERSION}-fpm"
success "PHP ${PHP_VERSION}-FPM mit OPcache konfiguriert."

# =============================================================================
# 4. MARIADB
# =============================================================================
section "$L_SECTION_4"

# Clean up previous MariaDB installation (prevents password conflicts on re-run)
if dpkg -l mariadb-server 2>/dev/null | grep -q '^ii'; then
  info "$L_MARIADB_CLEAN"
  systemctl stop mariadb 2>/dev/null || true
  echo "mariadb-server mariadb-server/postrm_remove_databases boolean true" \
    | debconf-set-selections 2>/dev/null || true
  DEBIAN_FRONTEND=noninteractive apt-get purge -y -qq --auto-remove \
    mariadb-server mariadb-client mariadb-common 2>/dev/null || true
  rm -rf /var/lib/mysql /etc/mysql/mariadb.conf.d/99-wordpress.cnf
  info "$L_MARIADB_CLEANED"
fi

apt-get install -y -qq mariadb-server mariadb-client
systemctl enable mariadb

# MariaDB Optimierungen (WooCommerce-optimiert)
cat > /etc/mysql/mariadb.conf.d/99-wordpress.cnf <<'MYCNF'
[mysqld]
# Zeichensatz
character-set-server  = utf8mb4
collation-server      = utf8mb4_unicode_ci
innodb_file_per_table = 1

# Performance (WooCommerce: größerer Buffer für Produktkatalog)
innodb_buffer_pool_size       = 512M
innodb_buffer_pool_instances  = 1
innodb_log_file_size          = 64M
innodb_log_buffer_size        = 16M
innodb_flush_log_at_trx_commit = 2
innodb_flush_method           = O_DIRECT
innodb_read_io_threads        = 4
innodb_write_io_threads       = 4

# Query Cache deaktiviert (WooCommerce: hohe Schreibrate macht Query Cache kontraproduktiv)
query_cache_type   = 0
query_cache_size   = 0

# Verbindungen
max_connections     = 150
max_allowed_packet  = 64M
thread_cache_size   = 8
table_open_cache    = 4000

# Slow Query Log
slow_query_log      = 1
slow_query_log_file = /var/log/mysql/slow.log
long_query_time     = 2

# Sicherheit
bind-address = 127.0.0.1
skip-name-resolve

[client]
default-character-set = utf8mb4
MYCNF

systemctl restart mariadb

# MariaDB absichern und DB anlegen
mysql -uroot <<SQLSETUP
-- Root behält unix_socket-Auth (sicherer auf Debian/Ubuntu — kein Passwort nötig bei OS-Root)
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost','127.0.0.1','::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQLSETUP

success "MariaDB konfiguriert und Datenbank '${DB_NAME}' erstellt."

# =============================================================================
# 5. REDIS OBJECT CACHE
# =============================================================================
section "$L_SECTION_5"
apt-get install -y -qq redis-server

cat > /etc/redis/redis.conf <<REDISCONF
# Redis Konfiguration — WooCommerce Object Cache
daemonize yes
supervised systemd
pidfile /var/run/redis/redis-server.pid
loglevel notice
logfile /var/log/redis/redis-server.log

# Netzwerk (nur localhost)
bind 127.0.0.1 -::1
port 6379
protected-mode yes
requirepass ${REDIS_PASS}

# Speicher (WooCommerce: 256mb für Object Cache + Sessions)
maxmemory 256mb
maxmemory-policy allkeys-lru
maxmemory-samples 5

# Persistenz deaktivieren (nur Cache)
save ""
appendonly no

# Performance
tcp-keepalive 300
timeout 300
tcp-backlog 511
REDISCONF

systemctl enable redis-server
systemctl restart redis-server
success "$L_REDIS_OK"

# =============================================================================
# 6. UFW FIREWALL + FAIL2BAN
# =============================================================================
section "$L_SECTION_6"
apt-get install -y -qq ufw fail2ban

# UFW Regeln
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable
success "$L_UFW_OK"

# Fail2ban — WordPress + WooCommerce + Nginx Jail
cat > /etc/fail2ban/jail.local <<'F2B'
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
banaction = ufw
ignoreip  = 127.0.0.1/8 ::1 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16

[sshd]
enabled  = true
port     = ssh
logpath  = %(sshd_log)s
maxretry = 3
bantime  = 24h

[nginx-http-auth]
enabled  = true
port     = http,https
logpath  = /var/log/nginx/*error.log

[nginx-limit-req]
enabled  = true
port     = http,https
logpath  = /var/log/nginx/*error.log
maxretry = 10

[wordpress-auth]
enabled  = true
port     = http,https
filter   = wordpress-auth
logpath  = /var/log/nginx/*access.log
maxretry = 5
bantime  = 24h

[woocommerce-checkout]
enabled  = true
port     = http,https
filter   = woocommerce-checkout
logpath  = /var/log/nginx/*access.log
maxretry = 5
findtime = 300
bantime  = 7200
F2B

# Fail2ban Filter für WP Login
cat > /etc/fail2ban/filter.d/wordpress-auth.conf <<'F2BFILTER'
[Definition]
failregex = ^<HOST> .* "POST /wp-login.php
            ^<HOST> .* "POST /xmlrpc.php
ignoreregex =
F2BFILTER

# Fail2ban Filter für WooCommerce Checkout (Carding-Schutz)
cat > /etc/fail2ban/filter.d/woocommerce-checkout.conf <<'F2BWCFILTER'
[Definition]
failregex = ^<HOST> .* "POST /checkout/.*" 40[013]
            ^<HOST> .* "POST /\?wc-ajax=checkout.*" 40[013]
ignoreregex =
F2BWCFILTER

systemctl enable fail2ban
systemctl restart fail2ban
success "$L_F2B_OK"

success "$L_F2B_WHITELIST"

# =============================================================================
# 7. WORDPRESS DOWNLOAD + KONFIGURATION
# =============================================================================
section "$L_SECTION_7"
mkdir -p "$WP_DIR"
cd /tmp

# WordPress herunterladen
curl -sSLo /tmp/wordpress.tar.gz "https://wordpress.org/latest.tar.gz"
tar -xzf /tmp/wordpress.tar.gz -C /tmp/
cp -a /tmp/wordpress/. "$WP_DIR/"
rm -rf /tmp/wordpress /tmp/wordpress.tar.gz

# Berechtigungen setzen
chown -R www-data:www-data "$WP_DIR"
find "$WP_DIR" -type d -exec chmod 755 {} \;
find "$WP_DIR" -type f -exec chmod 644 {} \;
chmod 640 "$WP_DIR/wp-config.php" 2>/dev/null || true

# wp-config.php erstellen
WP_SECURITY_KEYS=$(curl -sSL https://api.wordpress.org/secret-key/1.1/salt/)
PHP_MAX_MEMORY_LIMIT="$(( ${PHP_MEMORY_LIMIT%M} * 2 ))M"

cat > "$WP_DIR/wp-config.php" <<WPCONFIG
<?php
/**
 * WooCommerce Konfiguration — Auto-generiert von install-woocommerce.sh
 */

// ─── Datenbank ────────────────────────────────────────────────────────────────
define( 'DB_NAME',     '${DB_NAME}' );
define( 'DB_USER',     '${DB_USER}' );
define( 'DB_PASSWORD', '${DB_PASS}' );
define( 'DB_HOST',     'localhost' );
define( 'DB_CHARSET',  'utf8mb4' );
define( 'DB_COLLATE',  'utf8mb4_unicode_ci' );

// ─── Sicherheitsschlüssel (auto-generiert) ────────────────────────────────────
${WP_SECURITY_KEYS}

// ─── Datenbanktabellen-Präfix ─────────────────────────────────────────────────
\$table_prefix = 'wp_$(tr -dc 'a-z' </dev/urandom | head -c 4 || true)_';

// ─── Redis Object Cache ───────────────────────────────────────────────────────
define( 'WP_REDIS_HOST',     '127.0.0.1' );
define( 'WP_REDIS_PORT',     6379 );
define( 'WP_REDIS_PASSWORD', '${REDIS_PASS}' );
define( 'WP_REDIS_DATABASE', 0 );
define( 'WP_REDIS_TIMEOUT',  1 );
define( 'WP_REDIS_READ_TIMEOUT', 1 );
define( 'WP_REDIS_PREFIX',   '${DB_NAME}:' );

// ─── Performance ──────────────────────────────────────────────────────────────
define( 'WP_MEMORY_LIMIT',     '${PHP_MEMORY_LIMIT}' );
define( 'WP_MAX_MEMORY_LIMIT', '${PHP_MAX_MEMORY_LIMIT}' );
define( 'WP_POST_REVISIONS',   5 );
define( 'AUTOSAVE_INTERVAL',   300 );
define( 'EMPTY_TRASH_DAYS',    14 );
define( 'WP_CACHE',            true );

// ─── Sicherheit ───────────────────────────────────────────────────────────────
define( 'DISALLOW_FILE_EDIT', true );
define( 'FORCE_SSL_ADMIN',    true );
define( 'WP_DEBUG',           false );
define( 'WP_DEBUG_LOG',       false );
define( 'WP_DEBUG_DISPLAY',   false );
define( 'SCRIPT_DEBUG',       false );

// ─── Upload & Update ──────────────────────────────────────────────────────────
define( 'UPLOADS',            'wp-content/uploads' );
define( 'IMAGE_EDIT_OVERWRITE', true );

// ─── WooCommerce ──────────────────────────────────────────────────────────────
define( 'WC_LOG_HANDLER',   'WC_Log_Handler_File' );
define( 'WP_REDIS_MAXTTL',  86400 );

// ─── Multisite (deaktiviert) ──────────────────────────────────────────────────
// define( 'WP_ALLOW_MULTISITE', true );

if ( ! defined( 'ABSPATH' ) ) {
    define( 'ABSPATH', __DIR__ . '/' );
}
// ─── Reverse Proxy / HTTPS-Erkennung ─────────────────────────────────────────
if ( isset( \$_SERVER['HTTP_X_FORWARDED_PROTO'] ) && \$_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https' ) {
    \$_SERVER['HTTPS'] = 'on';
}

require_once ABSPATH . 'wp-settings.php';
WPCONFIG

chmod 640 "$WP_DIR/wp-config.php"
chown www-data:www-data "$WP_DIR/wp-config.php"

# .htaccess
cat > "$WP_DIR/.htaccess" <<'HTACCESS'
# BEGIN WordPress
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>
# END WordPress
HTACCESS

success "$L_WP_OK"

# =============================================================================
# 8. WP-CLI
# =============================================================================
section "$L_SECTION_8"
curl -sSLo /usr/local/bin/wp https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x /usr/local/bin/wp

# WP-CLI Cache in beschreibbares Verzeichnis umleiten (verhindert Permission-Warnungen)
export WP_CLI_CACHE_DIR=/tmp/wp-cli-cache
mkdir -p "$WP_CLI_CACHE_DIR"

# WP-CLI als www-data ausführen — Alias
cat > /usr/local/bin/wpcli <<ALIAS
#!/bin/bash
sudo -u www-data wp "\$@"
ALIAS
chmod +x /usr/local/bin/wpcli

# WordPress via WP-CLI installieren
sudo -u www-data wp core install \
  --path="$WP_DIR" \
  --url="http://${WP_DOMAIN}" \
  --title="${WP_SITE_TITLE}" \
  --admin_user="${WP_ADMIN_USER}" \
  --admin_password="${WP_ADMIN_PASS}" \
  --admin_email="${WP_ADMIN_EMAIL}" \
  --skip-email

# Redis Object Cache Plugin installieren & aktivieren
sudo -u www-data wp plugin install redis-cache --activate --path="$WP_DIR"
sudo -u www-data wp redis enable --path="$WP_DIR"

# Nginx Helper nur installieren — Aktivierung erfolgt NACH URL + Permalink Setup
sudo -u www-data wp plugin install nginx-helper --path="$WP_DIR"

# Standard-Plugins & Themes bereinigen
sudo -u www-data wp plugin delete hello akismet --path="$WP_DIR" 2>/dev/null || true
# Alle inaktiven Themes entfernen
sudo -u www-data wp theme list --status=inactive --field=name --path="$WP_DIR" 2>/dev/null \
  | xargs -r sudo -u www-data wp theme delete --path="$WP_DIR" 2>/dev/null || true

# Permalinks setzen (SEO-optimiert, WooCommerce-Anforderung)
sudo -u www-data wp rewrite structure '/%postname%/' --hard --path="$WP_DIR" 2>/dev/null
sudo -u www-data wp rewrite flush --hard --path="$WP_DIR" 2>/dev/null

# Standard-Einstellungen
sudo -u www-data wp option update timezone_string "${WP_TIMEZONE}" --path="$WP_DIR"
sudo -u www-data wp option update date_format "d.m.Y" --path="$WP_DIR"
sudo -u www-data wp option update time_format "H:i" --path="$WP_DIR"
sudo -u www-data wp option update WPLANG "${WP_LANG}" --path="$WP_DIR"
sudo -u www-data wp option update blogdescription "" --path="$WP_DIR"
sudo -u www-data wp option update comment_registration 1 --path="$WP_DIR"
sudo -u www-data wp option update default_ping_status closed --path="$WP_DIR"
sudo -u www-data wp option update default_comment_status closed --path="$WP_DIR"

# Bei Reverse Proxy oder SSL: siteurl und home auf HTTPS setzen
if [[ "$REVERSE_PROXY" == true || "$INSTALL_SSL" == true ]]; then
  sudo -u www-data wp option update siteurl "https://${WP_DOMAIN}" --path="$WP_DIR"
  sudo -u www-data wp option update home    "https://${WP_DOMAIN}" --path="$WP_DIR"
  info "$L_URLS_HTTPS"
fi

# Nginx Helper konfigurieren — Plugin bleibt deaktiviert, Nutzer aktiviert es manuell im WP Admin
sudo -u www-data wp option update rt_wp_nginx_helper_options \
  '{"enable_purge":"1","cache_method":"enable_fastcgi","purge_method":"get_request","nginx_server_hostname":"127.0.0.1","nginx_server_port":"80","enable_map":"0","enable_log":"0","log_level":"INFO","log_filesize":"5","enable_stamp":"0","purge_homepage_on_edit":"1","purge_homepage_on_del":"1","purge_archive_on_edit":"1","purge_archive_on_del":"1","purge_page_on_mod":"1","purge_page_on_new_comment":"1","purge_page_on_deleted_comment":"1"}' \
  --format=json --path="$WP_DIR"
success "$L_NGINX_HELPER_OK"

success "$L_WPCLI_OK"

# =============================================================================
# 9. WOOCOMMERCE
# =============================================================================
section "$L_SECTION_WC"

# WooCommerce installieren & aktivieren
sudo -u www-data wp plugin install woocommerce --activate --path="$WP_DIR"

# Basis-Konfiguration
sudo -u www-data wp option update woocommerce_default_country   "${WC_COUNTRY}"  --path="$WP_DIR"
sudo -u www-data wp option update woocommerce_currency          "${WC_CURRENCY}" --path="$WP_DIR"
sudo -u www-data wp option update woocommerce_currency_pos      "left"           --path="$WP_DIR"
sudo -u www-data wp option update woocommerce_price_num_decimals "2"             --path="$WP_DIR"

# Dezimaltrennzeichen je nach Währung anpassen
if [[ "$WC_CURRENCY" == "USD" || "$WC_CURRENCY" == "GBP" ]]; then
  sudo -u www-data wp option update woocommerce_price_thousand_sep "," --path="$WP_DIR"
  sudo -u www-data wp option update woocommerce_price_decimal_sep  "." --path="$WP_DIR"
else
  sudo -u www-data wp option update woocommerce_price_thousand_sep "." --path="$WP_DIR"
  sudo -u www-data wp option update woocommerce_price_decimal_sep  "," --path="$WP_DIR"
fi

# Tracking & Marketplace-Vorschläge deaktivieren (Datenschutz)
sudo -u www-data wp option update woocommerce_allow_tracking                   "no" --path="$WP_DIR"
sudo -u www-data wp option update woocommerce_show_marketplace_suggestions     "no" --path="$WP_DIR"
sudo -u www-data wp option add    woocommerce_merchant_email_notifications     "no" --path="$WP_DIR" 2>/dev/null || \
  sudo -u www-data wp option update woocommerce_merchant_email_notifications   "no" --path="$WP_DIR" 2>/dev/null || true

# Setup-Wizard als abgeschlossen markieren
sudo -u www-data wp option update woocommerce_onboarding_profile \
  '{"completed":true,"skipped":true}' --format=json --path="$WP_DIR"
sudo -u www-data wp option add woocommerce_task_list_hidden   "yes" --path="$WP_DIR" 2>/dev/null || \
  sudo -u www-data wp option update woocommerce_task_list_hidden   "yes" --path="$WP_DIR" 2>/dev/null || true
sudo -u www-data wp option add woocommerce_task_list_complete "yes" --path="$WP_DIR" 2>/dev/null || \
  sudo -u www-data wp option update woocommerce_task_list_complete "yes" --path="$WP_DIR" 2>/dev/null || true

# WooCommerce Standard-Seiten erstellen (Shop, Warenkorb, Kasse, Mein Konto)
sudo -u www-data wp wc tool run install_pages \
  --user="${WP_ADMIN_USER}" --path="$WP_DIR" 2>/dev/null || true

# DB-Tabellen sicherstellen
sudo -u www-data wp wc tool run verify_db_tables \
  --user="${WP_ADMIN_USER}" --path="$WP_DIR" 2>/dev/null || true

# Permalinks nach WooCommerce-Seiten-Erstellung neu einlesen
sudo -u www-data wp rewrite flush --hard --path="$WP_DIR"

# E-Mail Absender auf Admin-E-Mail setzen
sudo -u www-data wp option update woocommerce_email_from_address "${WP_ADMIN_EMAIL}" --path="$WP_DIR"
STORE_NAME=$(sudo -u www-data wp option get blogname --path="$WP_DIR" 2>/dev/null || echo "${WP_SITE_TITLE}")
sudo -u www-data wp option update woocommerce_email_from_name "${STORE_NAME}" --path="$WP_DIR"

success "$L_WC_OK"
success "$L_WC_PAGES"

# =============================================================================
# 10. LOGROTATE + CRON + FINALISIERUNG
# =============================================================================
section "$L_SECTION_9"

# cron-Daemon sicherstellen (auf Debian 13 nicht vorinstalliert)
if ! command -v crontab &>/dev/null; then
  apt-get install -y -qq --no-install-recommends cron
  systemctl enable cron 2>/dev/null || true
fi

# Logrotation für Nginx / PHP / MySQL
cat > /etc/logrotate.d/wordpress-stack <<'LOGROTATE'
/var/log/nginx/*.log {
    daily
    rotate 14
    compress
    delaycompress
    notifempty
    sharedscripts
    postrotate
        nginx -s reopen
    endscript
}

/var/log/php*-fpm*.log {
    daily
    rotate 14
    compress
    delaycompress
    notifempty
}

/var/log/mysql/slow.log {
    weekly
    rotate 4
    compress
    delaycompress
    notifempty
}
LOGROTATE

# WordPress Cron über System-Cron (WP-Cron deaktivieren)
cat >> "$WP_DIR/wp-config.php" <<'DISABLEWPCRON'

// WP-Cron über System-Cron ersetzen (performance)
define( 'DISABLE_WP_CRON', true );
DISABLEWPCRON

cat > /etc/cron.d/wordpress-cron <<WPCRON
* * * * * www-data /usr/local/bin/wp --path=${WP_DIR} cron event run --due-now --quiet
WPCRON
chmod 644 /etc/cron.d/wordpress-cron

# WooCommerce Action Scheduler (alle 2 Minuten — für Order-Status, E-Mails etc.)
cat > /etc/cron.d/woocommerce-scheduler <<WCCRON
*/2 * * * * www-data /usr/local/bin/wp --path=${WP_DIR} action-scheduler run --quiet 2>/dev/null || true
WCCRON
chmod 644 /etc/cron.d/woocommerce-scheduler

# WP-Cron einmalig direkt ausführen damit keine Events als "late" markiert werden
sudo -u www-data /usr/local/bin/wp --path="${WP_DIR}" cron event run --due-now --quiet 2>/dev/null || true
# Redis Cache Event explizit ausführen (wird beim Plugin-Aktivieren sofort geplant)
sudo -u www-data /usr/local/bin/wp --path="${WP_DIR}" cron event run rediscache_discard_metrics --quiet 2>/dev/null || true

# ─── Automatische Datenbank-Backups (täglich, 7 Tage Rotation) ────────────────
mkdir -p /root/backups/mysql
chmod 700 /root/backups/mysql
cat > /etc/cron.daily/wp-db-backup <<DBBACKUP
#!/bin/bash
BACKUP_DIR="/root/backups/mysql"
TIMESTAMP=\$(date +%Y%m%d_%H%M%S)
mysqldump -uroot --single-transaction --routines --triggers \
  '${DB_NAME}' | gzip > "\${BACKUP_DIR}/${DB_NAME}_\${TIMESTAMP}.sql.gz"
# Backups älter als 7 Tage löschen
find "\${BACKUP_DIR}" -name "*.sql.gz" -mtime +7 -delete
DBBACKUP
chmod 750 /etc/cron.daily/wp-db-backup
success "$L_BACKUPS_OK"

# ─── SSL mit Let's Encrypt (Certbot) ──────────────────────────────────────────
if [[ "$INSTALL_SSL" == true ]]; then
  info "Installiere Certbot und richte SSL ein..."
  apt-get install -y -qq certbot python3-certbot-nginx
  if certbot --nginx --non-interactive --agree-tos \
    -m "${WP_ADMIN_EMAIL}" \
    -d "${WP_DOMAIN}" \
    -d "www.${WP_DOMAIN}" \
    --redirect; then
    # HTTPS-Redirect im Vhost aktivieren
    sed -i 's|# return 301 https://|return 301 https://|' \
      "/etc/nginx/sites-available/${WP_DOMAIN}.conf"
    systemctl reload nginx
    success "$L_SSL_OK"
  else
    warn "$L_SSL_WARN"
    warn "$L_SSL_WARN2"
  fi
else
  info "$L_SSL_SKIP ${WP_DOMAIN}"
fi

# ─── phpMyAdmin ───────────────────────────────────────────────────────────────
if [[ "$INSTALL_PHPMYADMIN" == true ]]; then
  section "phpMyAdmin"
  PMA_DIR="/var/www/phpmyadmin"
  PMA_DOMAIN="phpmyadmin.${WP_DOMAIN}"

  # Aktuelle Version ermitteln
  PMA_VERSION=$(curl -fsSL https://www.phpmyadmin.net/home_page/version.txt 2>/dev/null | head -1 | tr -d '[:space:]') || true
  [[ -z "$PMA_VERSION" || ! "$PMA_VERSION" =~ ^[0-9]+\.[0-9]+ ]] && PMA_VERSION="5.2.2"
  info "phpMyAdmin Version: ${PMA_VERSION}"

  # Download & entpacken
  curl -fsSL "https://files.phpmyadmin.net/phpMyAdmin/${PMA_VERSION}/phpMyAdmin-${PMA_VERSION}-all-languages.tar.gz" \
    -o /tmp/phpmyadmin.tar.gz
  mkdir -p "$PMA_DIR"
  tar -xzf /tmp/phpmyadmin.tar.gz -C /tmp/
  cp -r "/tmp/phpMyAdmin-${PMA_VERSION}-all-languages/." "$PMA_DIR/"
  rm -rf /tmp/phpmyadmin.tar.gz "/tmp/phpMyAdmin-${PMA_VERSION}-all-languages"

  # Temp-Verzeichnis
  mkdir -p /var/lib/phpmyadmin/tmp
  chown -R www-data:www-data "$PMA_DIR" /var/lib/phpmyadmin
  chmod 750 "$PMA_DIR"

  # MariaDB-User für phpMyAdmin
  mysql -uroot <<SQLEOF
CREATE USER IF NOT EXISTS '${PMA_DB_USER}'@'localhost' IDENTIFIED BY '${PMA_DB_PASS}';
GRANT ALL PRIVILEGES ON *.* TO '${PMA_DB_USER}'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQLEOF

  # phpMyAdmin Konfiguration
  cat > "${PMA_DIR}/config.inc.php" <<PMACONFIG
<?php
\$cfg['blowfish_secret'] = '${PMA_BLOWFISH}';
\$i = 0;
\$i++;
\$cfg['Servers'][\$i]['auth_type']       = 'cookie';
\$cfg['Servers'][\$i]['host']            = 'localhost';
\$cfg['Servers'][\$i]['compress']        = false;
\$cfg['Servers'][\$i]['AllowNoPassword'] = false;
\$cfg['UploadDir']  = '';
\$cfg['SaveDir']    = '';
\$cfg['TempDir']    = '/var/lib/phpmyadmin/tmp';
\$cfg['CheckConfigurationPermissions'] = false;
PMACONFIG
  chown www-data:www-data "${PMA_DIR}/config.inc.php"
  chmod 640 "${PMA_DIR}/config.inc.php"

  # HTTP Basic Auth
  echo "${WP_ADMIN_USER}:$(openssl passwd -apr1 "${PMA_HTPASSWD_PASS}")" \
    > /etc/nginx/.phpmyadmin_htpasswd
  chmod 640 /etc/nginx/.phpmyadmin_htpasswd
  chown root:www-data /etc/nginx/.phpmyadmin_htpasswd

  # Nginx Vhost
  cat > "/etc/nginx/sites-available/${PMA_DOMAIN}.conf" <<NGINXPMA
server {
    listen 80;
    server_name ${PMA_DOMAIN};
    root ${PMA_DIR};
    index index.php;

    auth_basic "phpMyAdmin — Restricted";
    auth_basic_user_file /etc/nginx/.phpmyadmin_htpasswd;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php\$ {
        try_files \$uri =404;
        fastcgi_pass   php${PHP_VERSION}-fpm;
        fastcgi_index  index.php;
        include /etc/nginx/snippets/fastcgi-params-wp.conf;
    }

    location ~* /(README|LICENSE|ChangeLog|INSTALL|setup/) {
        deny all;
    }
    location ~* \.(htaccess|htpasswd|ini|log|sh|sql|bak)\$ {
        deny all;
    }
}
NGINXPMA

  ln -sf "/etc/nginx/sites-available/${PMA_DOMAIN}.conf" \
         "/etc/nginx/sites-enabled/${PMA_DOMAIN}.conf"
  nginx -t && systemctl reload nginx
  success "phpMyAdmin installiert unter http://${PMA_DOMAIN}"
  info "DNS/NPM: Subdomain ${PMA_DOMAIN} → Server-IP auf Port 80 konfigurieren."
fi

# ─── FileBrowser ──────────────────────────────────────────────────────────────
if [[ "$INSTALL_FILEBROWSER" == true ]]; then
  section "FileBrowser"
  FB_DOMAIN="files.${WP_DOMAIN}"
  FB_PORT=8082
  FB_DB="/var/lib/filebrowser/filebrowser.db"

  # Aktuelle Version ermitteln
  FB_VERSION=$(curl -fsSL https://api.github.com/repos/filebrowser/filebrowser/releases/latest \
    2>/dev/null | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/' || true)
  [[ -z "$FB_VERSION" || ! "$FB_VERSION" =~ ^[0-9] ]] && FB_VERSION="2.32.0"
  info "FileBrowser Version: ${FB_VERSION}"

  # Download
  curl -fsSL "https://github.com/filebrowser/filebrowser/releases/download/v${FB_VERSION}/linux-amd64-filebrowser.tar.gz" \
    -o /tmp/filebrowser.tar.gz
  tar -xzf /tmp/filebrowser.tar.gz -C /usr/local/bin/ filebrowser
  chmod +x /usr/local/bin/filebrowser
  rm -f /tmp/filebrowser.tar.gz

  mkdir -p /var/lib/filebrowser

  # Konfiguration & Admin-User anlegen
  filebrowser config init --database "$FB_DB"
  filebrowser config set --database "$FB_DB" \
    --address 127.0.0.1 \
    --port "$FB_PORT" \
    --root "${WP_DIR}" \
    --log /var/log/filebrowser.log
  filebrowser users add "${WP_ADMIN_USER}" "${FB_PASS}" --perm.admin \
    --database "$FB_DB"

  chown -R www-data:www-data /var/lib/filebrowser

  # Systemd Service
  cat > /etc/systemd/system/filebrowser.service <<FBSERVICE
[Unit]
Description=FileBrowser — Web File Manager
After=network.target

[Service]
User=www-data
Group=www-data
ExecStart=/usr/local/bin/filebrowser --database ${FB_DB}
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
FBSERVICE

  systemctl daemon-reload
  systemctl enable filebrowser
  systemctl start filebrowser

  # HTTP Basic Auth für FileBrowser
  echo "${WP_ADMIN_USER}:$(openssl passwd -apr1 "${FB_HTPASSWD_PASS}")" \
    > /etc/nginx/.filebrowser_htpasswd
  chmod 640 /etc/nginx/.filebrowser_htpasswd
  chown root:www-data /etc/nginx/.filebrowser_htpasswd

  # Nginx Vhost (Reverse Proxy zu FileBrowser)
  cat > "/etc/nginx/sites-available/${FB_DOMAIN}.conf" <<NGINXFB
server {
    listen 80;
    server_name ${FB_DOMAIN};

    location / {
        auth_basic "FileBrowser — Restricted";
        auth_basic_user_file /etc/nginx/.filebrowser_htpasswd;

        proxy_pass         http://127.0.0.1:${FB_PORT};
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade \$http_upgrade;
        proxy_set_header   Connection "upgrade";
        proxy_read_timeout 86400;
    }
}
NGINXFB

  ln -sf "/etc/nginx/sites-available/${FB_DOMAIN}.conf" \
         "/etc/nginx/sites-enabled/${FB_DOMAIN}.conf"
  nginx -t && systemctl reload nginx
  success "FileBrowser installiert unter http://${FB_DOMAIN}"
  info "DNS/NPM: Subdomain ${FB_DOMAIN} → Server-IP auf Port 80 konfigurieren."
fi

# MySQL Slow Log Verzeichnis anlegen
mkdir -p /var/log/mysql
chown mysql:mysql /var/log/mysql

# Abschließende Service-Neustarts
systemctl restart "php${PHP_VERSION}-fpm"
systemctl restart mariadb
systemctl restart redis-server
nginx -t && systemctl reload nginx

# Kurz warten bis alle Dienste stabil sind
sleep 3

# ─── Service-Status Abschlusskontrolle ────────────────────────────────────────
echo -e "\n${BOLD}Service-Status:${RESET}"
FAILED_SERVICES=()
for svc in nginx "php${PHP_VERSION}-fpm" mariadb redis-server fail2ban; do
  if systemctl is-active --quiet "$svc"; then
    echo -e "  ${GREEN}[OK]${RESET}    $svc"
  else
    echo -e "  ${RED}[FEHLER]${RESET} $svc — nicht aktiv! Versuche Neustart..."
    systemctl start "$svc" 2>/dev/null || true
    sleep 2
    if systemctl is-active --quiet "$svc"; then
      echo -e "  ${GREEN}[OK]${RESET}    $svc (nach Neustart)"
    else
      echo -e "  ${RED}[FEHLER]${RESET} $svc — Start fehlgeschlagen. Bitte prüfen: journalctl -u $svc"
      FAILED_SERVICES+=("$svc")
    fi
  fi
done

if [[ ${#FAILED_SERVICES[@]} -gt 0 ]]; then
  warn "Folgende Dienste konnten nicht gestartet werden: ${FAILED_SERVICES[*]}"
fi

# =============================================================================
# ABSCHLUSSBERICHT
# =============================================================================
section "WooCommerce erfolgreich installiert!"

echo -e ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${GREEN}║         WOOCOMMERCE ERFOLGREICH INSTALLIERT                  ║${RESET}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════╝${RESET}"
echo -e ""
SITE_PROTO="http"; [[ "$INSTALL_SSL" == true ]] && SITE_PROTO="https"
echo -e "  ${BOLD}Website URL:${RESET}      ${SITE_PROTO}://${WP_DOMAIN}"
echo -e "  ${BOLD}WP Admin:${RESET}         ${SITE_PROTO}://${WP_DOMAIN}/wp-admin"
echo -e "  ${BOLD}WC Admin:${RESET}         ${SITE_PROTO}://${WP_DOMAIN}/wp-admin/admin.php?page=wc-admin"
echo -e "  ${BOLD}Shop:${RESET}             ${SITE_PROTO}://${WP_DOMAIN}/shop"
echo -e "  ${BOLD}Admin User:${RESET}       ${WP_ADMIN_USER}"
echo -e "  ${BOLD}Admin Passwort:${RESET}   ${WP_ADMIN_PASS}"
echo -e "  ${BOLD}Admin Email:${RESET}      ${WP_ADMIN_EMAIL}"
echo -e ""
echo -e "  ${BOLD}WooCommerce:${RESET}      Währung: ${WC_CURRENCY}  |  Land: ${WC_COUNTRY}"
echo -e "  ${BOLD}Datenbank:${RESET}        ${DB_NAME} @ 127.0.0.1"
echo -e "  ${BOLD}DB Benutzer:${RESET}      ${DB_USER}"
echo -e "  ${BOLD}Redis:${RESET}            127.0.0.1:6379 (Object Cache aktiv)"
echo -e "  ${BOLD}PHP Version:${RESET}      ${PHP_VERSION} (Memory: ${PHP_MEMORY_LIMIT})"
echo -e "  ${BOLD}FastCGI Cache:${RESET}    ${NGINX_FASTCGI_CACHE_DIR}"
echo -e "  ${BOLD}DB Backup:${RESET}        /root/backups/mysql (täglich, 7 Tage)"
echo -e ""
echo -e "  ${BOLD}Credentials-Datei:${RESET}"
echo -e "    ${CYAN}${CREDS_FILE}${RESET}"
echo -e ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}NÄCHSTE SCHRITTE:${RESET}"
echo -e ""
if [[ "$INSTALL_SSL" == true ]]; then
echo -e "  ${GREEN}1. SSL bereits eingerichtet (Let's Encrypt aktiv)${RESET}"
else
echo -e "  ${BOLD}1. SSL-Zertifikat einrichten (für WooCommerce Checkout erforderlich):${RESET}"
echo -e "     ${CYAN}apt install -y certbot python3-certbot-nginx${RESET}"
echo -e "     ${CYAN}certbot --nginx -d ${WP_DOMAIN} -d www.${WP_DOMAIN}${RESET}"
fi
echo -e ""
echo -e "  ${BOLD}2. WooCommerce konfigurieren:${RESET}"
echo -e "     ${CYAN}${SITE_PROTO}://${WP_DOMAIN}/wp-admin/admin.php?page=wc-admin${RESET}"
echo -e "     - Zahlungsart einrichten (WooCommerce > Einstellungen > Zahlungen)"
echo -e "     - Versandzonen konfigurieren (WooCommerce > Einstellungen > Versand)"
echo -e "     - Steuereinstellungen prüfen (WooCommerce > Einstellungen > Steuern)"
echo -e ""
echo -e "  ${BOLD}3. Nginx Helper aktivieren:${RESET}"
echo -e "     ${CYAN}${SITE_PROTO}://${WP_DOMAIN}/wp-admin/plugins.php${RESET}"
echo -e "     (Nginx Helper Plugin aktivieren für automatischen Cache-Purge)"
echo -e ""
echo -e "  ${BOLD}4. DNS prüfen (A-Record zeigt auf diese IP):${RESET}"
echo -e "     ${CYAN}dig +short ${WP_DOMAIN}${RESET}"
echo -e ""
echo -e "  ${BOLD}5. FastCGI Cache testen (Shop-Seite sollte cachen, Cart nicht):${RESET}"
echo -e "     ${CYAN}curl -I http://${WP_DOMAIN}/shop | grep X-Cache-Status${RESET}"
echo -e "     ${CYAN}curl -I http://${WP_DOMAIN}/cart | grep X-Cache-Status${RESET}"
echo -e ""
echo -e "  ${BOLD}6. Redis Status prüfen:${RESET}"
echo -e "     ${CYAN}redis-cli -a '${REDIS_PASS}' ping${RESET}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e ""
warn "Alle Zugangsdaten wurden gespeichert in: ${CREDS_FILE}"
warn "HTTPS-Redirect in Nginx ist auskommentiert — nach Certbot aktivieren!"
echo -e ""
