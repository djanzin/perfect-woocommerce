#!/usr/bin/env bash
# =============================================================================
#  WooCommerce Stack Updater
#  Updates: WordPress core, WooCommerce, plugins, themes, WP-CLI, system, SSL
# =============================================================================
# Usage:
#   sudo bash update-woocommerce.sh
#   sudo bash update-woocommerce.sh --wp-path /var/www/wordpress --all
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

# ─── Root check ───────────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && error "Bitte als root ausführen: sudo bash $0"

# ─── Defaults ─────────────────────────────────────────────────────────────────
WP_PATH=""
UPDATE_SYSTEM=false
UPDATE_WPCLI=false
UPDATE_SSL=false
UPDATE_ALL=false
ENGLISH=false

# ─── Parse arguments ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --wp-path)   WP_PATH="$2";        shift 2 ;;
    --system)    UPDATE_SYSTEM=true;   shift   ;;
    --wpcli)     UPDATE_WPCLI=true;    shift   ;;
    --ssl)       UPDATE_SSL=true;      shift   ;;
    --all)       UPDATE_ALL=true;      shift   ;;
    --english)   ENGLISH=true;         shift   ;;
    *) warn "Unbekannter Parameter: $1"; shift ;;
  esac
done

if [[ "$UPDATE_ALL" == true ]]; then
  UPDATE_SYSTEM=true
  UPDATE_WPCLI=true
  UPDATE_SSL=true
fi

# ─── Sprachauswahl / Language selection ──────────────────────────────────────
if [[ "$ENGLISH" == false ]]; then
  echo -e "\n${BOLD}Sprache / Language:${RESET}"
  echo -e "  1) Deutsch  ${CYAN}[Standard / Default]${RESET}"
  echo -e "  2) English"
  read -rp "$(echo -e "${BOLD}Auswahl / Choice [1/2]:${RESET} ")" _lang_ui
  [[ "${_lang_ui}" == "2" ]] && ENGLISH=true
fi

# ─── Language strings ─────────────────────────────────────────────────────────
if [[ "$ENGLISH" == true ]]; then
  L_ROOT_ERR="Please run as root: sudo bash $0"
  L_UNKNOWN_PARAM="Unknown parameter"
  L_SECTION_HEADER="WooCommerce Stack Updater"
  L_WP_PATH="WordPress path"
  L_SYS_UPDATE="System update"
  L_WPCLI_UPDATE="WP-CLI update"
  L_SSL_RENEWAL="SSL renewal"
  L_SECTION_SYS="System Update"
  L_SYS_OK="System packages updated."
  L_SECTION_WPCLI="WP-CLI Update"
  L_WPCLI_CURRENT="Current version"
  L_WPCLI_UPDATED="WP-CLI updated to"
  L_WPCLI_NOT_FOUND="WP-CLI not found — skipping."
  L_SECTION_CORE="WordPress Core Update"
  L_CORE_CURRENT="Current WP version"
  L_CORE_UPDATED="WordPress core updated"
  L_CORE_OK="WordPress core is up to date"
  L_SECTION_PLUGINS="Plugin Updates"
  L_PLUGINS_FOUND="plugin(s) with available updates..."
  L_PLUGINS_OK="All plugins are up to date."
  L_PLUGINS_UPDATED="All plugins updated."
  L_SECTION_WC="WooCommerce Database Migration"
  L_WC_ACTIVE="WooCommerce active — running database migration..."
  L_WC_DB_OK="WooCommerce database tables updated."
  L_WC_LOOKUP_OK="WooCommerce product lookup tables updated."
  L_WC_NOT_ACTIVE="WooCommerce not active — skipping DB migration."
  L_SECTION_THEMES="Theme Updates"
  L_THEMES_FOUND="theme(s) with available updates..."
  L_THEMES_OK="All themes are up to date."
  L_THEMES_UPDATED="All themes updated."
  L_SECTION_CACHE="Clear Cache"
  L_CACHE_WP="WordPress object cache cleared."
  L_CACHE_NGINX="Nginx FastCGI cache cleared."
  L_CACHE_NGINX_RELOAD="Nginx reloaded."
  L_CACHE_PHP="PHP-FPM OPcache cleared."
  L_CACHE_OK="All caches cleared."
  L_SECTION_PMA="phpMyAdmin Update"
  L_PMA_INSTALLED="Installed version"
  L_PMA_UPDATING="Updating phpMyAdmin"
  L_PMA_OK="phpMyAdmin is up to date"
  L_PMA_UPDATED="phpMyAdmin updated to"
  L_PMA_FETCH_ERR="Could not fetch latest phpMyAdmin version — skipping."
  L_SECTION_FB="FileBrowser Update"
  L_FB_INSTALLED="Installed version"
  L_FB_UPDATING="Updating FileBrowser"
  L_FB_OK="FileBrowser is up to date"
  L_FB_UPDATED="FileBrowser updated to"
  L_FB_FETCH_ERR="Could not fetch latest FileBrowser version — skipping."
  L_SECTION_SSL="Renew SSL Certificate"
  L_SSL_OK="SSL certificates renewed."
  L_SSL_WARN="Certbot renewal failed — may already be up to date or reverse proxy active."
  L_SSL_NOT_FOUND="Certbot not installed — skipping."
  L_SECTION_STATUS="Service Status"
  L_WP_NOT_FOUND="WordPress not found. Specify path: --wp-path /path/to/wordpress"
  L_DONE="Update complete"
else
  L_ROOT_ERR="Bitte als root ausführen: sudo bash $0"
  L_UNKNOWN_PARAM="Unbekannter Parameter"
  L_SECTION_HEADER="WooCommerce Stack Updater"
  L_WP_PATH="WordPress-Pfad"
  L_SYS_UPDATE="System-Update"
  L_WPCLI_UPDATE="WP-CLI Update"
  L_SSL_RENEWAL="SSL Renewal"
  L_SECTION_SYS="System-Update"
  L_SYS_OK="System-Pakete aktualisiert."
  L_SECTION_WPCLI="WP-CLI Update"
  L_WPCLI_CURRENT="Aktuelle Version"
  L_WPCLI_UPDATED="WP-CLI aktualisiert auf"
  L_WPCLI_NOT_FOUND="WP-CLI nicht gefunden — überspringe."
  L_SECTION_CORE="WordPress Core Update"
  L_CORE_CURRENT="Aktuelle WP-Version"
  L_CORE_UPDATED="WordPress Core aktualisiert"
  L_CORE_OK="WordPress Core ist aktuell"
  L_SECTION_PLUGINS="Plugin-Updates"
  L_PLUGINS_FOUND="Plugin(s) mit verfügbaren Updates..."
  L_PLUGINS_OK="Alle Plugins sind aktuell."
  L_PLUGINS_UPDATED="Alle Plugins aktualisiert."
  L_SECTION_WC="WooCommerce Datenbank-Migration"
  L_WC_ACTIVE="WooCommerce aktiv — führe Datenbank-Migration durch..."
  L_WC_DB_OK="WooCommerce Datenbank-Tabellen aktualisiert."
  L_WC_LOOKUP_OK="WooCommerce Produkt-Lookup-Tabellen aktualisiert."
  L_WC_NOT_ACTIVE="WooCommerce nicht aktiv — überspringe DB-Migration."
  L_SECTION_THEMES="Theme-Updates"
  L_THEMES_FOUND="Theme(s) mit verfügbaren Updates..."
  L_THEMES_OK="Alle Themes sind aktuell."
  L_THEMES_UPDATED="Alle Themes aktualisiert."
  L_SECTION_CACHE="Cache leeren"
  L_CACHE_WP="WordPress Object Cache geleert."
  L_CACHE_NGINX="Nginx FastCGI Cache geleert."
  L_CACHE_NGINX_RELOAD="Nginx neu geladen."
  L_CACHE_PHP="PHP-FPM OPcache geleert."
  L_CACHE_OK="Alle Caches geleert."
  L_SECTION_PMA="phpMyAdmin Update"
  L_PMA_INSTALLED="Installierte Version"
  L_PMA_UPDATING="Aktualisiere phpMyAdmin"
  L_PMA_OK="phpMyAdmin ist aktuell"
  L_PMA_UPDATED="phpMyAdmin aktualisiert auf"
  L_PMA_FETCH_ERR="phpMyAdmin Latest-Version konnte nicht abgerufen werden — überspringe."
  L_SECTION_FB="FileBrowser Update"
  L_FB_INSTALLED="Installierte Version"
  L_FB_UPDATING="Aktualisiere FileBrowser"
  L_FB_OK="FileBrowser ist aktuell"
  L_FB_UPDATED="FileBrowser aktualisiert auf"
  L_FB_FETCH_ERR="FileBrowser Latest-Version konnte nicht abgerufen werden — überspringe."
  L_SECTION_SSL="SSL-Zertifikat erneuern"
  L_SSL_OK="SSL-Zertifikate erneuert."
  L_SSL_WARN="Certbot Renewal fehlgeschlagen — ggf. bereits aktuell oder Reverse Proxy aktiv."
  L_SSL_NOT_FOUND="Certbot nicht installiert — überspringe."
  L_SECTION_STATUS="Service-Status"
  L_WP_NOT_FOUND="WordPress nicht gefunden. Pfad angeben: --wp-path /pfad/zu/wordpress"
  L_DONE="Update abgeschlossen"
fi

# ─── WordPress Pfad ermitteln ─────────────────────────────────────────────────
if [[ -z "$WP_PATH" ]]; then
  for candidate in /var/www/wordpress /var/www/html /var/www/*/; do
    if [[ -f "${candidate}/wp-config.php" ]]; then
      WP_PATH="$candidate"
      break
    fi
  done
fi

[[ -z "$WP_PATH" || ! -f "${WP_PATH}/wp-config.php" ]] && \
  error "$L_WP_NOT_FOUND"

WP_DOMAIN=$(basename "$WP_PATH")
[[ "$WP_DOMAIN" == "wordpress" ]] && \
  WP_DOMAIN=$(grep -i "WP_HOME\|siteurl" "${WP_PATH}/wp-config.php" 2>/dev/null \
    | head -1 | sed "s/.*['\"]https\?:\/\/\([^'\"]*\)['\"].*/\1/" || echo "wordpress")

WP_BIN=$(command -v wp 2>/dev/null || true)
[[ -z "$WP_BIN" || ! -x "$WP_BIN" ]] && WP_BIN="/usr/local/bin/wp"
WP_CLI=("$WP_BIN" --path="$WP_PATH" --allow-root)

section "$L_SECTION_HEADER"
echo -e "  $L_WP_PATH    : ${CYAN}${WP_PATH}${RESET}"
echo -e "  $L_SYS_UPDATE  : ${CYAN}${UPDATE_SYSTEM}${RESET}"
echo -e "  $L_WPCLI_UPDATE: ${CYAN}${UPDATE_WPCLI}${RESET}"
echo -e "  $L_SSL_RENEWAL : ${CYAN}${UPDATE_SSL}${RESET}"
echo ""

# ─── 1. System-Pakete ─────────────────────────────────────────────────────────
if [[ "$UPDATE_SYSTEM" == true ]]; then
  section "$L_SECTION_SYS"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get upgrade -y -qq
  success "$L_SYS_OK"
fi

# ─── 2. WP-CLI ────────────────────────────────────────────────────────────────
if [[ "$UPDATE_WPCLI" == true ]]; then
  section "$L_SECTION_WPCLI"
  if command -v wp &>/dev/null; then
    WP_CLI_CURRENT=$(wp --info --allow-root 2>/dev/null | grep 'WP-CLI version' | awk '{print $3}' || echo "unbekannt")
    info "$L_WPCLI_CURRENT: ${WP_CLI_CURRENT}"
    curl -fsSL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
      -o /usr/local/bin/wp
    chmod +x /usr/local/bin/wp
    WP_CLI_NEW=$(wp --info --allow-root 2>/dev/null | grep 'WP-CLI version' | awk '{print $3}' || echo "unbekannt")
    success "$L_WPCLI_UPDATED ${WP_CLI_NEW}."
  else
    warn "$L_WPCLI_NOT_FOUND"
  fi
fi

# ─── 3. WordPress Core ────────────────────────────────────────────────────────
section "$L_SECTION_CORE"
WP_VERSION_BEFORE=$("${WP_CLI[@]}" core version 2>/dev/null || echo "unbekannt")
info "$L_CORE_CURRENT: ${WP_VERSION_BEFORE}"

if "${WP_CLI[@]}" core check-update 2>/dev/null | grep -q 'update available'; then
  "${WP_CLI[@]}" core update
  "${WP_CLI[@]}" core update-db
  WP_VERSION_AFTER=$("${WP_CLI[@]}" core version 2>/dev/null || echo "unbekannt")
  success "$L_CORE_UPDATED: ${WP_VERSION_BEFORE} → ${WP_VERSION_AFTER}"
else
  success "$L_CORE_OK (${WP_VERSION_BEFORE})."
fi

# ─── 4. Plugins ───────────────────────────────────────────────────────────────
section "$L_SECTION_PLUGINS"
PLUGINS_WITH_UPDATES=$("${WP_CLI[@]}" plugin list --update=available --format=count 2>/dev/null || echo "0")
if [[ "$PLUGINS_WITH_UPDATES" -gt 0 ]]; then
  info "${PLUGINS_WITH_UPDATES} $L_PLUGINS_FOUND"
  "${WP_CLI[@]}" plugin update --all
  success "$L_PLUGINS_UPDATED"
else
  success "$L_PLUGINS_OK"
fi

# ─── 5. WooCommerce Datenbank-Migration ───────────────────────────────────────
section "$L_SECTION_WC"
if "${WP_CLI[@]}" plugin is-active woocommerce 2>/dev/null; then
  info "$L_WC_ACTIVE"
  # WooCommerce DB-Update nach Plugin-Updates
  "${WP_CLI[@]}" wc update 2>/dev/null || true
  success "$L_WC_DB_OK"
  # Produkt-Lookup-Tabellen neu aufbauen
  "${WP_CLI[@]}" wc tool run update_product_lookup_tables \
    --user=1 --path="$WP_PATH" 2>/dev/null || true
  success "$L_WC_LOOKUP_OK"
  # Action Scheduler abarbeiten
  "${WP_CLI[@]}" action-scheduler run --quiet 2>/dev/null || true
else
  warn "$L_WC_NOT_ACTIVE"
fi

# ─── 6. Themes ────────────────────────────────────────────────────────────────
section "$L_SECTION_THEMES"
THEMES_WITH_UPDATES=$("${WP_CLI[@]}" theme list --update=available --format=count 2>/dev/null || echo "0")
if [[ "$THEMES_WITH_UPDATES" -gt 0 ]]; then
  info "${THEMES_WITH_UPDATES} $L_THEMES_FOUND"
  "${WP_CLI[@]}" theme update --all
  success "$L_THEMES_UPDATED"
else
  success "$L_THEMES_OK"
fi

# ─── 7. Cache leeren ──────────────────────────────────────────────────────────
section "$L_SECTION_CACHE"

# WordPress & Redis Cache
"${WP_CLI[@]}" cache flush 2>/dev/null && info "$L_CACHE_WP" || true

# FastCGI Cache leeren
if [[ -d "/var/cache/nginx/fastcgi" ]]; then
  find /var/cache/nginx/fastcgi -type f -delete 2>/dev/null || true
  success "$L_CACHE_NGINX"
fi

# Nginx neu laden
nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null && \
  info "$L_CACHE_NGINX_RELOAD" || true

# PHP-FPM OPcache leeren
PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" 2>/dev/null || echo "8.3")
systemctl restart "php${PHP_VERSION}-fpm" 2>/dev/null && \
  info "$L_CACHE_PHP" || true

success "$L_CACHE_OK"

# ─── 8. phpMyAdmin aktualisieren ─────────────────────────────────────────────
PMA_DIR="/var/www/phpmyadmin"
if [[ -d "$PMA_DIR" ]]; then
  section "$L_SECTION_PMA"
  PMA_CURRENT=$(grep -oP "(?<=VERSION = ')[\d.]+" "${PMA_DIR}/libraries/classes/Version.php" 2>/dev/null \
    | head -1 || \
    grep -oP "(?<=\"version\": \")[\d.]+" "${PMA_DIR}/composer.json" 2>/dev/null \
    | head -1 || \
    php -r "define('ROOT_PATH', '${PMA_DIR}/'); \
      require '${PMA_DIR}/libraries/classes/Version.php'; \
      echo \PhpMyAdmin\Version::VERSION;" 2>/dev/null \
    || echo "unbekannt")
  info "$L_PMA_INSTALLED: ${PMA_CURRENT}"

  PMA_LATEST=$(curl -fsSL https://www.phpmyadmin.net/home_page/version.txt 2>/dev/null \
    | head -1 | tr -d '[:space:]') || true

  if [[ -z "$PMA_LATEST" ]]; then
    warn "$L_PMA_FETCH_ERR"
  elif [[ "$PMA_CURRENT" == "$PMA_LATEST" ]]; then
    success "$L_PMA_OK (${PMA_CURRENT})."
  else
    info "$L_PMA_UPDATING: ${PMA_CURRENT} → ${PMA_LATEST}"
    curl -fsSL "https://files.phpmyadmin.net/phpMyAdmin/${PMA_LATEST}/phpMyAdmin-${PMA_LATEST}-all-languages.tar.gz" \
      -o /tmp/phpmyadmin.tar.gz
    tar -xzf /tmp/phpmyadmin.tar.gz -C /tmp/
    [[ -f "${PMA_DIR}/config.inc.php" ]] && \
      cp "${PMA_DIR}/config.inc.php" /tmp/phpmyadmin_config.inc.php.bak
    rsync -a --exclude="config.inc.php" \
      "/tmp/phpMyAdmin-${PMA_LATEST}-all-languages/" "${PMA_DIR}/"
    [[ -f /tmp/phpmyadmin_config.inc.php.bak ]] && \
      cp /tmp/phpmyadmin_config.inc.php.bak "${PMA_DIR}/config.inc.php"
    rm -rf /tmp/phpmyadmin.tar.gz "/tmp/phpMyAdmin-${PMA_LATEST}-all-languages"
    chown -R www-data:www-data "$PMA_DIR"
    success "$L_PMA_UPDATED ${PMA_LATEST}."
  fi
fi

# ─── 9. FileBrowser aktualisieren ────────────────────────────────────────────
FB_BIN="/usr/local/bin/filebrowser"
if [[ -x "$FB_BIN" ]]; then
  section "$L_SECTION_FB"
  FB_CURRENT=$("$FB_BIN" version 2>/dev/null | grep -oP "v[\d.]+" | head -1 | tr -d 'v' || echo "unbekannt")
  info "$L_FB_INSTALLED: ${FB_CURRENT}"

  FB_LATEST=$(curl -fsSL https://api.github.com/repos/filebrowser/filebrowser/releases/latest \
    2>/dev/null | grep '"tag_name"' | head -1 | grep -oP '[\d.]+') || true

  if [[ -z "$FB_LATEST" ]]; then
    warn "$L_FB_FETCH_ERR"
  elif [[ "$FB_CURRENT" == "$FB_LATEST" ]]; then
    success "$L_FB_OK (${FB_CURRENT})."
  else
    info "$L_FB_UPDATING: ${FB_CURRENT} → ${FB_LATEST}"
    systemctl stop filebrowser 2>/dev/null || true
    curl -fsSL "https://github.com/filebrowser/filebrowser/releases/download/v${FB_LATEST}/linux-amd64-filebrowser.tar.gz" \
      -o /tmp/filebrowser.tar.gz
    tar -xzf /tmp/filebrowser.tar.gz -C /usr/local/bin/ filebrowser
    chmod +x "$FB_BIN"
    rm -f /tmp/filebrowser.tar.gz
    systemctl start filebrowser 2>/dev/null || true
    success "$L_FB_UPDATED ${FB_LATEST}."
  fi
fi

# ─── 10. SSL-Zertifikat erneuern ──────────────────────────────────────────────
if [[ "$UPDATE_SSL" == true ]]; then
  section "$L_SECTION_SSL"
  if command -v certbot &>/dev/null; then
    certbot renew --quiet --nginx 2>/dev/null && \
      success "$L_SSL_OK" || \
      warn "$L_SSL_WARN"
  else
    warn "$L_SSL_NOT_FOUND"
  fi
fi

# ─── 11. Service-Status ───────────────────────────────────────────────────────
section "$L_SECTION_STATUS"
for svc in nginx "php${PHP_VERSION}-fpm" mariadb redis-server filebrowser; do
  if systemctl is-active --quiet "$svc" 2>/dev/null; then
    echo -e "  ${GREEN}[OK]${RESET}    $svc"
  else
    echo -e "  ${YELLOW}[WARN]${RESET}  $svc — nicht aktiv"
  fi
done

# ─── Abschluss ────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}${GREEN}════════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}${GREEN}  $L_DONE — $(date '+%Y-%m-%d %H:%M')${RESET}"
echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════════${RESET}\n"
