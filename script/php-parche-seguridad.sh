#!/usr/bin/env bash
# actualizar-php.sh
# Actualiza SOLO los paquetes de PHP instalados (parches de seguridad) en Ubuntu.
# No cambia de version mayor (8.3 sigue siendo 8.3): Ubuntu entrega los parches
# de seguridad como versiones nuevas del mismo paquete (ej. 8.3.6-0ubuntu0.24.04.x).
#
# Uso:
#   sudo ./actualizar-php.sh            # actualiza y reinicia servicios
#   sudo ./actualizar-php.sh --simular  # solo muestra que se actualizaria
#   sudo ./actualizar-php.sh --sin-reinicio

set -euo pipefail

SIMULAR=0
REINICIAR=1
for arg in "$@"; do
  case "$arg" in
    --simular)      SIMULAR=1 ;;
    --sin-reinicio) REINICIAR=0 ;;
    -h|--help)
      sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "Opcion desconocida: $arg" >&2; exit 1 ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  echo "Ejecuta con sudo: sudo $0 $*" >&2
  exit 1
fi

LOG="/var/log/actualizar-php.log"
exec > >(tee -a "$LOG") 2>&1
echo "=== $(date '+%F %T') - Inicio actualizacion PHP ==="

# 1) Paquetes PHP instalados (php8.3, php8.3-cli, php8.3-fpm, php8.3-pgsql, etc.)
mapfile -t PAQUETES < <(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 'php*' 2>/dev/null \
  | awk '$1 ~ /^ii/ {print $2}')

if [[ ${#PAQUETES[@]} -eq 0 ]]; then
  echo "No hay paquetes PHP instalados con apt. Nada que hacer."
  exit 0
fi

echo "Version actual: $(php -v 2>/dev/null | head -n1 || echo 'php no esta en el PATH')"
echo "Paquetes PHP detectados: ${#PAQUETES[@]}"

# 2) Backup de configuracion (php.ini, pools de FPM, etc.)
if [[ $SIMULAR -eq 0 ]]; then
  BACKUP="/var/backups/php-etc-$(date +%F_%H%M%S).tar.gz"
  tar -czf "$BACKUP" /etc/php 2>/dev/null && echo "Backup de /etc/php: $BACKUP"
fi

# 3) Actualizar indices
apt-get update -qq

# 4) Actualizar solo esos paquetes (sin instalar nuevos ni tocar otros)
if [[ $SIMULAR -eq 1 ]]; then
  echo "--- SIMULACION (no se cambia nada) ---"
  apt-get install --only-upgrade --dry-run "${PAQUETES[@]}"
  exit 0
fi

DEBIAN_FRONTEND=noninteractive apt-get install --only-upgrade -y \
  -o Dpkg::Options::="--force-confold" "${PAQUETES[@]}"

echo "Version nueva: $(php -v 2>/dev/null | head -n1 || true)"

# 5) Reiniciar PHP-FPM / Apache / Nginx si corresponde
if [[ $REINICIAR -eq 1 ]]; then
  reiniciar() {
    local svc="$1"
    if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
      systemctl is-active --quiet "$svc" && { systemctl restart "$svc" && echo "Reiniciado: $svc"; }
    else
      # WSL sin systemd
      service "$svc" status >/dev/null 2>&1 && { service "$svc" restart && echo "Reiniciado: $svc"; }
    fi
  }

  for fpm in /lib/systemd/system/php*-fpm.service; do
    [[ -e "$fpm" ]] && reiniciar "$(basename "$fpm" .service)"
  done
  reiniciar apache2 || true
  # Nginx no ejecuta PHP; solo se recarga por si hubo cambios en el socket de FPM
  if command -v nginx >/dev/null 2>&1 && nginx -t >/dev/null 2>&1; then
    reiniciar nginx || true
  fi
fi

# 6) Avisar si el sistema pide reinicio
[[ -f /var/run/reboot-required ]] && echo "AVISO: el sistema indica que requiere reinicio."

echo "=== $(date '+%F %T') - Fin ==="
