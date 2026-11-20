#!/usr/bin/env bash
# parchear-php.sh
# Aplica los parches de seguridad de PHP en Ubuntu: actualiza SOLO los paquetes
# de PHP ya instalados, sin cambiar de version mayor (8.3 sigue siendo 8.3).
# Ubuntu entrega los parches como una revision nueva del mismo paquete
# (ej. 8.3.6-0ubuntu0.24.04.x).
#
# Servicios: recarga PHP-FPM (reload). Nginx no se toca. Apache solo se
# reinicia si PHP corre como modulo (libapache2-mod-php).
#
# Uso:
#   sudo ./parchear-php.sh             # parchea y recarga servicios
#   sudo ./parchear-php.sh --simular   # solo muestra que se actualizaria
#   sudo ./parchear-php.sh --sin-reinicio

set -euo pipefail

SIMULAR=0
REINICIAR=1
for arg in "$@"; do
  case "$arg" in
    --simular)      SIMULAR=1 ;;
    --sin-reinicio) REINICIAR=0 ;;
    -h|--help)      sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "Opcion desconocida: $arg" >&2; exit 1 ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  echo "Ejecuta con sudo: sudo $0 $*" >&2
  exit 1
fi

LOG="/var/log/parchear-php.log"
exec > >(tee -a "$LOG") 2>&1
echo "=== $(date '+%F %T') - Inicio parche PHP ==="

# 1) Paquetes instalados: php* y el modulo de Apache (libapache2-mod-php*)
mapfile -t PAQUETES < <(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 'php*' 'libapache2-mod-php*' 2>/dev/null \
  | awk '$1 ~ /^ii/ {print $2}')

if [[ ${#PAQUETES[@]} -eq 0 ]]; then
  echo "No hay paquetes PHP instalados con apt. Nada que hacer."
  exit 0
fi

echo "Version actual: $(php -v 2>/dev/null | head -n1 || echo 'php no esta en el PATH')"
echo "Paquetes detectados: ${#PAQUETES[@]}"

# 2) Backup de configuracion
if [[ $SIMULAR -eq 0 ]]; then
  BACKUP="/var/backups/php-etc-$(date +%F_%H%M%S).tar.gz"
  tar -czf "$BACKUP" /etc/php 2>/dev/null && echo "Backup de /etc/php: $BACKUP"
fi

# 3) Actualizar indices
apt-get update -qq

# 4) Simulacion o actualizacion real (solo esos paquetes)
if [[ $SIMULAR -eq 1 ]]; then
  echo "--- SIMULACION (no se cambia nada) ---"
  apt-get install --only-upgrade --dry-run "${PAQUETES[@]}"
  exit 0
fi

DEBIAN_FRONTEND=noninteractive apt-get install --only-upgrade -y \
  -o Dpkg::Options::="--force-confold" "${PAQUETES[@]}"

echo "Version nueva: $(php -v 2>/dev/null | head -n1 || true)"

# 5) Recargar servicios
if [[ $REINICIAR -eq 1 ]]; then
  usa_systemd() { command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; }

  accion() {   # accion <reload|restart> <servicio>
    local act="$1" svc="$2"
    if usa_systemd; then
      systemctl is-active --quiet "$svc" && systemctl "$act" "$svc" && echo "${act}: $svc"
    else  # WSL sin systemd
      service "$svc" status >/dev/null 2>&1 && service "$svc" "$act" && echo "${act}: $svc"
    fi
  }

  # PHP-FPM: reload (los workers terminan sus peticiones antes de salir)
  for unidad in /lib/systemd/system/php*-fpm.service; do
    [[ -e "$unidad" ]] && { accion reload "$(basename "$unidad" .service)" || true; }
  done

  # Apache: solo si PHP corre como modulo (mod_php)
  if dpkg-query -W -f='${db:Status-Abbrev}\n' 'libapache2-mod-php*' 2>/dev/null | grep -q '^ii'; then
    accion restart apache2 || true
  fi
  # Nginx: no se toca (solo pasa peticiones a PHP-FPM por socket)
fi

# 6) Avisar si el sistema pide reinicio
[[ -f /var/run/reboot-required ]] && echo "AVISO: el sistema indica que requiere reinicio."

echo "=== $(date '+%F %T') - Fin ==="
