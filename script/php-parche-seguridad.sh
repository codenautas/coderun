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
# Sin opciones y desde una terminal, muestra un menu de acciones (ver estado,
# simular, parchear, parchear sin recargar servicios). Si hay mas de una version
# instalada, despues pide elegir una o todas.
#
# Uso:
#   sudo ./parchear-php.sh                 # menu de acciones y de versiones
#   sudo ./parchear-php.sh --simular       # solo muestra que se actualizaria
#   sudo ./parchear-php.sh --sin-reinicio
#   sudo ./parchear-php.sh --version 8.3   # sin menu: solo esa version
#   sudo ./parchear-php.sh --todas         # sin menu: todas las versiones
#   (sin terminal interactiva y sin --version/--todas, se parchean todas)

set -euo pipefail

SIMULAR=0
REINICIAR=1
ELEGIDA=""   # "" = preguntar, "todas", o "X.Y"
SIN_ARGS=0; [[ $# -eq 0 ]] && SIN_ARGS=1   # sin opciones -> menu de acciones
while [[ $# -gt 0 ]]; do
  case "$1" in
    --simular)      SIMULAR=1 ;;
    --sin-reinicio) REINICIAR=0 ;;
    --todas)        ELEGIDA="todas" ;;
    --version)
      [[ -n "${2:-}" ]] || { echo "--version requiere un valor (ej. 8.3)" >&2; exit 1; }
      ELEGIDA="$2"; shift ;;
    -h|--help)      sed -n '2,/^$/p' "$0"; exit 0 ;;
    *) echo "Opcion desconocida: $1" >&2; exit 1 ;;
  esac
  shift
done

if [[ $EUID -ne 0 ]]; then
  echo "Ejecuta con sudo: sudo $0 $*" >&2
  exit 1
fi

# Proxy HTTPS solo para estas llamadas de apt (no modifica la config del sistema).
# Se toma del propio sistema: primero el proxy HTTP efectivo de apt, y si no hay,
# la variable http_proxy. Se puede forzar con: PROXY_HTTPS_APT=http://host:puerto sudo -E ./parchear-php.sh
# Si el sistema no tiene proxy, no se agrega ninguna opcion.
if [[ -z "${PROXY_HTTPS_APT:-}" ]]; then
  PROXY_HTTPS_APT=$(apt-config dump 2>/dev/null | sed -n 's/^Acquire::http::Proxy "\(.*\)";$/\1/p' | head -n1)
fi
[[ -z "$PROXY_HTTPS_APT" ]] && PROXY_HTTPS_APT="${http_proxy:-}"
[[ -n "$PROXY_HTTPS_APT" && "$PROXY_HTTPS_APT" != *://* ]] && PROXY_HTTPS_APT="http://$PROXY_HTTPS_APT"
APT_OPTS=()
[[ -n "$PROXY_HTTPS_APT" ]] && APT_OPTS=(-o "Acquire::https::Proxy=$PROXY_HTTPS_APT")

LOG="/var/log/parchear-php.log"
exec > >(tee -a "$LOG") 2>&1
echo "=== $(date '+%F %T') - Inicio parche PHP ==="

# 1) Paquetes instalados CON version en el nombre (php8.3, php8.3-fpm, php8.3-pgsql,
#    libapache2-mod-php8.3) mas php-common. Se excluyen a proposito los metapaquetes
#    sin version (php, php-fpm, php-cli, php-json...): apuntan a la version "por defecto"
#    del repositorio y, al actualizarlos, pueden instalar OTRA version mayor (ej. 8.4).
mapfile -t PAQUETES < <(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 'php*' 'libapache2-mod-php*' 2>/dev/null \
  | awk '$1 ~ /^ii/ {print $2}' \
  | grep -E '^(php[0-9]+\.[0-9]+(-.*)?|libapache2-mod-php[0-9]+\.[0-9]+|php-common)$')

if [[ ${#PAQUETES[@]} -eq 0 ]]; then
  echo "No hay paquetes PHP instalados con apt. Nada que hacer."
  exit 0
fi

# Versiones mayores instaladas (ej. 8.1, 8.3)
mapfile -t VERSIONES < <(printf '%s\n' "${PAQUETES[@]}" \
  | grep -oE '^(php|libapache2-mod-php)[0-9]+\.[0-9]+' | grep -oE '[0-9]+\.[0-9]+$' | sort -uV)

# Revision instalada de una version (ej. "8.3" -> "8.3.6-0ubuntu0.24.04.1")
revision() {
  dpkg-query -W -f='${Version}' "php${1}-common" 2>/dev/null \
    || dpkg-query -W -f='${Version}' "php${1}" 2>/dev/null || true
}

# Muestra cada version de PHP seleccionada con su revision instalada
listar_versiones() {
  local v
  for v in "${VERSIONES[@]}"; do echo "  PHP ${v}: $(revision "$v")"; done
}

# Actualizar indices (necesario para saber si hay parches disponibles)
echo "Actualizando indices de apt..."
apt-get "${APT_OPTS[@]}" update -qq

# Estado de parche de cada version: simula la actualizacion de sus paquetes
# y cuenta cuantos tienen una revision nueva disponible.
declare -A ESTADO
for v in "${VERSIONES[@]}"; do
  VRE="${v//./[.]}"   # 8.3 -> 8[.]3 para usar en regex
  mapfile -t PKGS_V < <(printf '%s\n' "${PAQUETES[@]}" \
    | grep -E "^(php${VRE}(-.*)?|libapache2-mod-php${VRE})$")
  ACT=$(apt-get "${APT_OPTS[@]}" -s install --only-upgrade "${PKGS_V[@]}" 2>/dev/null \
    | grep '^Inst' | grep '\[' || true)
  if [[ -z "$ACT" ]]; then
    ESTADO[$v]="$(revision "$v")  [al dia]"
  else
    N=$(wc -l <<<"$ACT")
    # Linea de referencia: phpX.Y-common si esta, si no la primera
    # Formato: "Inst php8.3-common [8.3.6-0ubuntu0.24.04.1] (8.3.6-0ubuntu0.24.04.2 Ubuntu:...)"
    REF=$(grep -E "^Inst php${VRE}-common " <<<"$ACT" || head -n1 <<<"$ACT")
    DE=$(sed -n 's/^Inst [^ ]* \[\([^]]*\)\].*/\1/p' <<<"$REF" | head -n1)
    A=$(sed -n 's/^Inst [^ ]* \[[^]]*\] (\([^ ]*\).*/\1/p' <<<"$REF" | head -n1)
    ESTADO[$v]="$DE -> $A  [PARCHE DISPONIBLE: $N paquete(s)]"
  fi
done

# 1a) Menu de acciones (solo sin opciones y con terminal interactiva)
if [[ $SIN_ARGS -eq 1 && -t 0 ]]; then
  while true; do
    echo
    echo "Que queres hacer?"
    echo "  1) Ver versiones de PHP y parches disponibles"
    echo "  2) Simular el parche (no cambia nada)"
    echo "  3) Aplicar el parche y recargar servicios"
    echo "  4) Aplicar el parche sin recargar servicios"
    echo "  0) Salir"
    read -r -p "Elegi una opcion: " ACC
    case "$ACC" in
      1) echo "Versiones de PHP instaladas:"
         for v in "${VERSIONES[@]}"; do echo "  PHP ${v}: ${ESTADO[$v]}"; done ;;
      2) SIMULAR=1; break ;;
      3) break ;;
      4) REINICIAR=0; break ;;
      0) echo "Saliendo sin cambios."; exit 0 ;;
      *) echo "Opcion invalida." ;;
    esac
  done
fi

# 1b) Elegir version(es) a parchear
if [[ ${#VERSIONES[@]} -gt 1 && -z "$ELEGIDA" ]]; then
  if [[ -t 0 ]]; then
    echo "Versiones de PHP instaladas:"
    for i in "${!VERSIONES[@]}"; do
      echo "  $((i + 1))) PHP ${VERSIONES[$i]}: ${ESTADO[${VERSIONES[$i]}]}"
    done
    echo "  0) Todas"
    while true; do
      read -r -p "Elegi una opcion [0]: " OPC
      OPC="${OPC:-0}"
      if [[ "$OPC" == "0" ]]; then
        ELEGIDA="todas"; break
      elif [[ "$OPC" =~ ^[0-9]+$ ]] && (( OPC >= 1 && OPC <= ${#VERSIONES[@]} )); then
        ELEGIDA="${VERSIONES[$((OPC - 1))]}"; break
      fi
      echo "Opcion invalida."
    done
  else
    ELEGIDA="todas"   # sin terminal (cron, pipe): comportamiento anterior
  fi
fi

if [[ -n "$ELEGIDA" && "$ELEGIDA" != "todas" ]]; then
  if ! printf '%s\n' "${VERSIONES[@]}" | grep -qxF "$ELEGIDA"; then
    echo "PHP $ELEGIDA no esta instalado. Instaladas: ${VERSIONES[*]}" >&2
    exit 1
  fi
  VERSIONES=("$ELEGIDA")
  # Solo paquetes de esa version (php-common es compartido y se mantiene)
  mapfile -t PAQUETES < <(printf '%s\n' "${PAQUETES[@]}" \
    | grep -E "^(php${ELEGIDA//./[.]}(-.*)?|libapache2-mod-php${ELEGIDA//./[.]}|php-common)$")
fi

echo "Versiones de PHP a parchear:"
for v in "${VERSIONES[@]}"; do echo "  PHP ${v}: ${ESTADO[$v]}"; done
echo "Consola (php -v): $(php -v 2>/dev/null | head -n1 || echo 'php no esta en el PATH')"
echo "Paquetes a actualizar: ${#PAQUETES[@]}"

# 2) Backup de configuracion
if [[ $SIMULAR -eq 0 ]]; then
  BACKUP="/var/backups/php-etc-$(date +%F_%H%M%S).tar.gz"
  tar -czf "$BACKUP" /etc/php 2>/dev/null && echo "Backup de /etc/php: $BACKUP"
fi

# 4) Simulacion previa + guarda de seguridad.
#    Un parche solo debe ACTUALIZAR paquetes ya instalados ("Inst nombre [vieja] (nueva)").
#    Si apt quisiera instalar un paquete nuevo (sin [version vieja]) o quitar alguno,
#    se aborta sin tocar nada: seria un cambio de version y no un parche.
SIM=$(apt-get "${APT_OPTS[@]}" -s install --only-upgrade "${PAQUETES[@]}")
NUEVOS=$(grep '^Inst' <<<"$SIM" | grep -v '\[' || true)
QUITAR=$(grep '^Remv' <<<"$SIM" || true)
if [[ -n "$NUEVOS" || -n "$QUITAR" ]]; then
  echo "ABORTADO: la actualizacion instalaria o quitaria paquetes (no es solo un parche)."
  [[ -n "$NUEVOS" ]] && { echo "Paquetes NUEVOS que instalaria:"; echo "$NUEVOS"; }
  [[ -n "$QUITAR" ]] && { echo "Paquetes que quitaria:"; echo "$QUITAR"; }
  echo "No se modifico nada. Revisa 'apt-cache policy php' y los repositorios."
  exit 1
fi

if [[ $SIMULAR -eq 1 ]]; then
  echo "--- SIMULACION (no se cambia nada). Paquetes que se actualizarian: ---"
  grep '^Inst' <<<"$SIM" || echo "(ninguno: ya esta todo al dia)"
  exit 0
fi

DEBIAN_FRONTEND=noninteractive apt-get "${APT_OPTS[@]}" install --only-upgrade -y \
  -o Dpkg::Options::="--force-confold" "${PAQUETES[@]}"

echo "Versiones de PHP despues del parche:"
listar_versiones

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

  # PHP-FPM: reload solo de las versiones parcheadas
  # (los workers terminan sus peticiones antes de salir)
  for v in "${VERSIONES[@]}"; do
    [[ -e "/lib/systemd/system/php${v}-fpm.service" || -e "/etc/init.d/php${v}-fpm" ]] \
      && { accion reload "php${v}-fpm" || true; }
  done

  # Apache: solo si alguna version parcheada corre como modulo (mod_php)
  if printf '%s\n' "${PAQUETES[@]}" | grep -q '^libapache2-mod-php'; then
    accion restart apache2 || true
  fi
  # Nginx: no se toca (solo pasa peticiones a PHP-FPM por socket)
fi

# 6) Avisar si el sistema pide reinicio
#    Solo si el reinicio pendiente lo pidio un paquete de PHP (no por kernel, libc, etc.)
if [[ -f /var/run/reboot-required.pkgs ]] && grep -qE '^(php|libapache2-mod-php)' /var/run/reboot-required.pkgs; then
  echo "AVISO: un paquete de PHP requiere reiniciar el sistema."
fi

echo "=== $(date '+%F %T') - Fin ==="
