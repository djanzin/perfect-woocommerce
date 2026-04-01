#!/usr/bin/env bash
# =============================================================================
#  WooCommerce Stack Reset
#  Entfernt: WordPress, WooCommerce, Nginx, PHP-FPM, MariaDB, Redis, Fail2ban,
#             WP-CLI, phpMyAdmin, FileBrowser, SSL, Cron-Jobs, Swap
# =============================================================================
# Usage:
#   sudo bash reset-woocommerce.sh
#
# Läuft ohne Rückfragen durch und entfernt alles was install-woocommerce.sh
# installiert und konfiguriert hat.
# =============================================================================

set -uo pipefail
IFS=$'\n\t'

# ─── Colour helpers ───────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
section() { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${RESET}"; \
            echo -e "${BOLD}${CYAN}  $*${RESET}"; \
            echo -e "${BOLD}${CYAN}══════════════════════════════════════════${RESET}"; }

# ─── Root check ───────────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && { echo "Bitte als root ausführen: sudo bash $0"; exit 1; }

# ─── Defaults ─────────────────────────────────────────────────────────────────
ENGLISH=false

# ─── Parse arguments ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --english) ENGLISH=true; shift ;;
    *) shift ;;
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

# ─── Language strings ─────────────────────────────────────────────────────────
if [[ "$ENGLISH" == true ]]; then
  L_ROOT_ERR="Please run as root: sudo bash $0"
  L_SECTION_HEADER="WooCommerce Stack Reset"
  L_WP_PATH_LABEL="WordPress path"
  L_DOMAIN_LABEL="Domain"
  L_PHP_LABEL="PHP version"
  L_DB_LABEL="Database"
  L_SECTION_SERVICES="Stop Services"
  L_SERVICES_OK="Services stopped."
  L_SECTION_WP="Remove WordPress & WooCommerce"
  L_WP_REMOVED="WordPress directory removed"
  L_WP_NOT_FOUND="No WordPress directory found."
  L_SECTION_PMA="Remove phpMyAdmin"
  L_PMA_REMOVED="phpMyAdmin removed."
  L_SECTION_FB="Remove FileBrowser"
  L_FB_REMOVED="FileBrowser removed."
  L_SECTION_DB="Remove Database"
  L_DB_NOT_RUNNING="MariaDB not running — database will be removed during uninstall."
  L_SECTION_NGINX="Remove Nginx Configuration"
  L_NGINX_OK="Nginx configuration removed."
  L_SECTION_PHP="Remove PHP-FPM Configuration"
  L_PHP_OK="PHP-FPM configuration removed."
  L_SECTION_F2B="Remove Fail2ban Configuration"
  L_F2B_OK="Fail2ban configuration removed."
  L_SECTION_CRON="Remove Cron Jobs"
  L_CRON_OK="Cron jobs removed."
  L_SECTION_SSL="Remove SSL Certificate"
  L_SSL_REMOVED="SSL certificate removed."
  L_SSL_NOT_FOUND="No SSL certificate found or already removed."
  L_SSL_NO_CERTBOT="Certbot not installed — skipping."
  L_SECTION_WPCLI="Remove WP-CLI"
  L_WPCLI_OK="WP-CLI removed."
  L_SECTION_CREDS="Remove Credentials and Backups"
  L_CREDS_OK="Credentials and backups removed."
  L_SECTION_PKGS="Uninstall Packages"
  L_PKGS_OK="Packages uninstalled."
  L_SECTION_SWAP="Remove Swap"
  L_SWAP_REMOVED="Swap file removed."
  L_SWAP_NOT_FOUND="No swap file found — skipping."
  L_DONE="Reset complete"
  L_REBOOT="Recommendation: restart the server with 'reboot'"
  L_NOT_FOUND="not found"
  L_UNKNOWN="unknown"
  L_DB_DROPPED="Database dropped"
  L_DB_USER_DROPPED="DB user dropped"
  L_SVC_STOPPED="stopped"
else
  L_ROOT_ERR="Bitte als root ausführen: sudo bash $0"
  L_SECTION_HEADER="WooCommerce Stack Reset"
  L_WP_PATH_LABEL="WordPress-Pfad"
  L_DOMAIN_LABEL="Domain"
  L_PHP_LABEL="PHP-Version"
  L_DB_LABEL="Datenbank"
  L_SECTION_SERVICES="Services stoppen"
  L_SERVICES_OK="Services gestoppt."
  L_SECTION_WP="WordPress & WooCommerce entfernen"
  L_WP_REMOVED="WordPress-Verzeichnis entfernt"
  L_WP_NOT_FOUND="Kein WordPress-Verzeichnis gefunden."
  L_SECTION_PMA="phpMyAdmin entfernen"
  L_PMA_REMOVED="phpMyAdmin entfernt."
  L_SECTION_FB="FileBrowser entfernen"
  L_FB_REMOVED="FileBrowser entfernt."
  L_SECTION_DB="Datenbank entfernen"
  L_DB_NOT_RUNNING="MariaDB läuft nicht — Datenbank wird beim Deinstallieren entfernt."
  L_SECTION_NGINX="Nginx-Konfiguration entfernen"
  L_NGINX_OK="Nginx-Konfiguration entfernt."
  L_SECTION_PHP="PHP-FPM-Konfiguration entfernen"
  L_PHP_OK="PHP-FPM-Konfiguration entfernt."
  L_SECTION_F2B="Fail2ban-Konfiguration entfernen"
  L_F2B_OK="Fail2ban-Konfiguration entfernt."
  L_SECTION_CRON="Cron-Jobs entfernen"
  L_CRON_OK="Cron-Jobs entfernt."
  L_SECTION_SSL="SSL-Zertifikat entfernen"
  L_SSL_REMOVED="SSL-Zertifikat entfernt."
  L_SSL_NOT_FOUND="Kein SSL-Zertifikat gefunden oder bereits entfernt."
  L_SSL_NO_CERTBOT="Certbot nicht installiert — überspringe."
  L_SECTION_WPCLI="WP-CLI entfernen"
  L_WPCLI_OK="WP-CLI entfernt."
  L_SECTION_CREDS="Credentials und Backups entfernen"
  L_CREDS_OK="Credentials und Backups entfernt."
  L_SECTION_PKGS="Pakete deinstallieren"
  L_PKGS_OK="Pakete deinstalliert."
  L_SECTION_SWAP="Swap entfernen"
  L_SWAP_REMOVED="Swap-Datei entfernt."
  L_SWAP_NOT_FOUND="Keine Swap-Datei gefunden — überspringe."
  L_DONE="Reset abgeschlossen"
  L_REBOOT="Empfehlung: Server neu starten mit 'reboot'"
  L_NOT_FOUND="nicht gefunden"
  L_UNKNOWN="unbekannt"
  L_DB_DROPPED="Datenbank gelöscht"
  L_DB_USER_DROPPED="DB-User gelöscht"
  L_SVC_STOPPED="gestoppt"
fi

# ─── WordPress-Pfad & Domain ermitteln ────────────────────────────────────────
WP_PATH=""
for candidate in /var/www/wordpress /var/www/html /var/www/*/; do
  [[ -f "${candidate}/wp-config.php" ]] && WP_PATH="$candidate" && break
done

WP_DOMAIN=""
if [[ -n "$WP_PATH" ]]; then
  WP_DOMAIN=$(grep -iE "WP_HOME|siteurl" "${WP_PATH}/wp-config.php" 2>/dev/null \
    | head -1 | sed "s/.*['\"]https\?:\/\/\([^'\"]*\)['\"].*/\1/" || true)
  [[ -z "$WP_DOMAIN" ]] && WP_DOMAIN=$(basename "$WP_PATH")
fi

# ─── PHP-Version ermitteln ────────────────────────────────────────────────────
PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" 2>/dev/null || true)
if [[ -z "$PHP_VERSION" ]]; then
  PHP_VERSION=$(find /etc/php -maxdepth 1 -mindepth 1 -type d 2>/dev/null \
    | sort -V | tail -1 | xargs basename || echo "")
fi

# ─── DB-Credentials aus wp-config.php ─────────────────────────────────────────
DB_NAME=""
DB_USER=""
if [[ -n "$WP_PATH" && -f "${WP_PATH}/wp-config.php" ]]; then
  DB_NAME=$(grep "DB_NAME" "${WP_PATH}/wp-config.php" \
    | grep -oP "(?<=')[^']+(?=')" | head -1 || true)
  DB_USER=$(grep "DB_USER" "${WP_PATH}/wp-config.php" \
    | grep -oP "(?<=')[^']+(?=')" | head -1 || true)
fi

section "$L_SECTION_HEADER"
echo -e "  $L_WP_PATH_LABEL : ${CYAN}${WP_PATH:-$L_NOT_FOUND}${RESET}"
echo -e "  $L_DOMAIN_LABEL  : ${CYAN}${WP_DOMAIN:-$L_UNKNOWN}${RESET}"
echo -e "  $L_PHP_LABEL     : ${CYAN}${PHP_VERSION:-$L_UNKNOWN}${RESET}"
echo -e "  $L_DB_LABEL      : ${CYAN}${DB_NAME:-$L_UNKNOWN}${RESET}"
echo ""

# ─── 1. Services stoppen ──────────────────────────────────────────────────────
section "$L_SECTION_SERVICES"
for svc in filebrowser nginx "php${PHP_VERSION}-fpm" redis-server fail2ban; do
  if systemctl is-active --quiet "$svc" 2>/dev/null; then
    systemctl stop "$svc" 2>/dev/null && info "$svc $L_SVC_STOPPED." || true
  fi
  systemctl disable "$svc" 2>/dev/null || true
done
success "$L_SERVICES_OK"

# ─── 2. WordPress-Dateien ─────────────────────────────────────────────────────
section "$L_SECTION_WP"
if [[ -n "$WP_PATH" && -d "$WP_PATH" ]]; then
  rm -rf "$WP_PATH"
  success "$L_WP_REMOVED: ${WP_PATH}"
else
  warn "$L_WP_NOT_FOUND"
fi

# ─── 3. phpMyAdmin ────────────────────────────────────────────────────────────
if [[ -d "/var/www/phpmyadmin" ]]; then
  section "$L_SECTION_PMA"
  rm -rf /var/www/phpmyadmin /var/lib/phpmyadmin
  rm -f /etc/nginx/.phpmyadmin_htpasswd
  success "$L_PMA_REMOVED"
fi

# ─── 4. FileBrowser ───────────────────────────────────────────────────────────
if [[ -f "/usr/local/bin/filebrowser" || -d "/var/lib/filebrowser" ]]; then
  section "$L_SECTION_FB"
  systemctl stop filebrowser 2>/dev/null || true
  systemctl disable filebrowser 2>/dev/null || true
  rm -f /usr/local/bin/filebrowser
  rm -rf /var/lib/filebrowser
  rm -f /etc/systemd/system/filebrowser.service
  systemctl daemon-reload
  success "$L_FB_REMOVED"
fi

# ─── 5. Datenbank & User ──────────────────────────────────────────────────────
section "$L_SECTION_DB"
if systemctl is-active --quiet mariadb 2>/dev/null; then
  [[ -n "$DB_NAME" ]] && \
    mysql -e "DROP DATABASE IF EXISTS \`${DB_NAME}\`;" 2>/dev/null && \
    success "$L_DB_DROPPED: ${DB_NAME}" || true

  [[ -n "$DB_USER" && "$DB_USER" != "root" ]] && \
    mysql -e "DROP USER IF EXISTS '${DB_USER}'@'localhost';" 2>/dev/null && \
    success "$L_DB_USER_DROPPED: ${DB_USER}" || true

  mysql -e "DROP USER IF EXISTS 'phpmyadmin'@'localhost';" 2>/dev/null || true
  mysql -e "FLUSH PRIVILEGES;" 2>/dev/null || true
else
  warn "$L_DB_NOT_RUNNING"
fi

# ─── 6. Nginx-Konfiguration ───────────────────────────────────────────────────
section "$L_SECTION_NGINX"
if [[ -n "$WP_DOMAIN" ]]; then
  rm -f "/etc/nginx/sites-enabled/${WP_DOMAIN}" \
        "/etc/nginx/sites-available/${WP_DOMAIN}" \
        "/etc/nginx/sites-enabled/phpmyadmin.${WP_DOMAIN}" \
        "/etc/nginx/sites-available/phpmyadmin.${WP_DOMAIN}" \
        "/etc/nginx/sites-enabled/files.${WP_DOMAIN}" \
        "/etc/nginx/sites-available/files.${WP_DOMAIN}"
fi
rm -f /etc/nginx/conf.d/fastcgi-cache.conf \
      /etc/nginx/conf.d/real-ip.conf \
      /etc/nginx/conf.d/rate-limiting.conf
rm -rf /var/cache/nginx/fastcgi
success "$L_NGINX_OK"

# ─── 7. PHP-FPM-Konfiguration ─────────────────────────────────────────────────
if [[ -n "$PHP_VERSION" ]]; then
  section "$L_SECTION_PHP"
  rm -f "/etc/php/${PHP_VERSION}/fpm/pool.d/wordpress.conf" \
        "/etc/php/${PHP_VERSION}/fpm/conf.d/99-opcache-wordpress.ini"
  [[ ! -f "/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf" ]] && \
    cp "/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf.dpkg-dist" \
       "/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf" 2>/dev/null || true
  success "$L_PHP_OK"
fi

# ─── 8. Fail2ban ──────────────────────────────────────────────────────────────
section "$L_SECTION_F2B"
rm -f /etc/fail2ban/jail.local \
      /etc/fail2ban/filter.d/wordpress-auth.conf \
      /etc/fail2ban/filter.d/woocommerce-checkout.conf
success "$L_F2B_OK"

# ─── 9. Cron-Jobs ─────────────────────────────────────────────────────────────
section "$L_SECTION_CRON"
rm -f /etc/cron.d/wordpress-cron \
      /etc/cron.d/woocommerce-scheduler \
      /etc/cron.daily/wp-db-backup
success "$L_CRON_OK"

# ─── 10. Log-Rotation ─────────────────────────────────────────────────────────
rm -f /etc/logrotate.d/wordpress-stack

# ─── 11. SSL-Zertifikat ───────────────────────────────────────────────────────
section "$L_SECTION_SSL"
if command -v certbot &>/dev/null && [[ -n "$WP_DOMAIN" ]]; then
  certbot delete --cert-name "$WP_DOMAIN" --non-interactive 2>/dev/null && \
    success "$L_SSL_REMOVED" || \
    warn "$L_SSL_NOT_FOUND"
else
  warn "$L_SSL_NO_CERTBOT"
fi

# ─── 12. WP-CLI ───────────────────────────────────────────────────────────────
section "$L_SECTION_WPCLI"
rm -f /usr/local/bin/wp
success "$L_WPCLI_OK"

# ─── 13. Credentials & Backups ────────────────────────────────────────────────
section "$L_SECTION_CREDS"
rm -f /root/.wp_install_credentials_*.txt
rm -rf /root/backups/mysql
success "$L_CREDS_OK"

# ─── 14. Pakete deinstallieren ────────────────────────────────────────────────
section "$L_SECTION_PKGS"
export DEBIAN_FRONTEND=noninteractive
echo "mariadb-server mariadb-server/postrm_remove_databases boolean true" \
  | debconf-set-selections 2>/dev/null || true

PHP_PKGS=()
if [[ -n "$PHP_VERSION" ]]; then
  for pkg in fpm mysql redis xml mbstring curl zip gd intl bcmath imagick; do
    PHP_PKGS+=("php${PHP_VERSION}-${pkg}")
  done
  PHP_PKGS+=("php${PHP_VERSION}")
fi

apt-get purge -y -qq \
  nginx nginx-common \
  libnginx-mod-http-cache-purge \
  libnginx-mod-http-brotli-filter \
  libnginx-mod-http-brotli-static \
  "${PHP_PKGS[@]}" \
  mariadb-server mariadb-client mariadb-common \
  redis-server redis-tools \
  fail2ban \
  certbot python3-certbot-nginx \
  cron 2>/dev/null || true

apt-get autoremove -y -qq 2>/dev/null || true
apt-get autoclean -qq 2>/dev/null || true
success "$L_PKGS_OK"

# ─── 15. Swap-Datei ───────────────────────────────────────────────────────────
section "$L_SECTION_SWAP"
if [[ -f /swapfile ]]; then
  swapoff /swapfile 2>/dev/null || true
  sed -i '/\/swapfile/d' /etc/fstab
  sed -i '/vm.swappiness/d' /etc/sysctl.conf
  rm -f /swapfile
  success "$L_SWAP_REMOVED"
else
  info "$L_SWAP_NOT_FOUND"
fi

# ─── Abschluss ────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}${GREEN}════════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}${GREEN}  $L_DONE — $(date '+%Y-%m-%d %H:%M')${RESET}"
echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════════${RESET}"
echo ""
warn "$L_REBOOT"
echo ""
