#!/usr/bin/env bash
# revisar-versiones.sh
#
# Compara las versiones instaladas de Ubuntu, PHP, nginx, Caddy, PostgreSQL y
# Node.js contra una tabla fija de versiones vigentes al 2026-10-22.
#
# Uso:   sudo bash revisar-versiones.sh
#        (sin sudo funciona, pero no ve los procesos de otros usuarios)
#
# Limitaciones conocidas:
# - La tabla es fija: con el paso del tiempo las "últimas versiones" envejecen.
# - Ubuntu aplica parches de seguridad sin cambiar la versión base del paquete.
#   Para esos paquetes (marcados con *) el indicador confiable es si apt tiene
#   una actualización pendiente, no la comparación con la tabla.
# - Por seguridad, solo ejecuta binarios que pertenecen a root o al usuario
#   actual y que no son modificables por el grupo ni por otros usuarios.
#   Para los demás intenta deducir la versión a partir de la ruta (caso nvm).
# - Las instalaciones de nvm se buscan en /opt/.nvm (ubicación del instructivo
#   de instalación), en $NVM_DIR, en /root y en /home/*; sin sudo no se pueden
#   leer los home de otros usuarios.
#
# Código de salida: 0 sin observaciones; 1 con al menos una observación.

set -u
shopt -s nullglob

readonly NOMBRE="revisar-versiones"
readonly VERSION="0.1.0"
readonly TABLA_FECHA="2026-10-22"

# ---------------------------------------------------------------------------
# Tablas de versiones (fuente única para todo el script).
# Formato: rama|última versión|observación (vacía si no hay nada que señalar)
# La primera línea de cada tabla es la rama más nueva.
# ---------------------------------------------------------------------------
readonly TABLA_PHP='8.5|8.5.12|
8.4|8.4.27|
8.3|8.3.36|
8.2|8.2.35|la rama 8.2 deja de recibir correcciones de seguridad el 2026-12-31'

readonly TABLA_NGINX='1.31|1.31.8|
1.30|1.30.6|'

readonly TABLA_CADDY='2.11|2.11.7|'

readonly TABLA_POSTGRES='18|18.6|
17|17.11|
16|16.15|
15|15.19|
14|14.24|la rama 14 deja de recibir correcciones el 2026-11-12'

readonly TABLA_NODE='26|26.12.1|
24|24.22.1|
22|22.23.4|'

# Formato: versión|fin del soporte estándar|observación
readonly TABLA_UBUNTU='26.10|2027-07|
26.04|2031-04|
24.04|2029-04|
22.04|2027-04|quedan menos de seis meses de soporte estándar'

# ---------------------------------------------------------------------------
# Estado global
# ---------------------------------------------------------------------------
observaciones=0
hay_paquetes_ubuntu=0
PENDIENTES=""
declare -a PROC_RUTAS=()
declare -A PROC_REEMPLAZADOS=()
declare -A EN_EJECUCION=()

informar() { # nivel mensaje
    printf '%-12s %s\n' "$1" "$2"
    case "$1" in
        "ATENCIÓN"|"SIN-SOPORTE") observaciones=$((observaciones + 1)) ;;
    esac
}

titulo() {
    printf '\n== %s ==\n' "$1"
}

# ---------------------------------------------------------------------------
# Obtención de versiones (cada función recibe la ruta absoluta del binario)
# ---------------------------------------------------------------------------
version_php()      { timeout 10 "$1" -v 2>/dev/null | head -n1 | grep -oE '^PHP [0-9]+\.[0-9]+\.[0-9]+' | cut -d' ' -f2; }
version_nginx()    { timeout 10 "$1" -v 2>&1 | grep -oE 'nginx/[0-9]+\.[0-9]+\.[0-9]+' | head -n1 | cut -d/ -f2; }
version_caddy()    { timeout 10 "$1" version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n1 | cut -c2-; }
version_node()     { timeout 10 "$1" -v 2>/dev/null | grep -oE '^v[0-9]+\.[0-9]+\.[0-9]+' | cut -c2-; }
version_postgres() { timeout 10 "$1" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -n1; }

version_desde_ruta() { # ruta → p. ej. /home/x/.nvm/versions/node/v22.2.0/bin/node → 22.2.0
    grep -oE '/v?[0-9]+\.[0-9]+(\.[0-9]+)?/' <<<"$1" | tail -n1 | tr -d '/v'
}

se_puede_ejecutar() { # ruta
    local ruta="$1" duenio modo
    [[ -f "$ruta" && -x "$ruta" ]] || return 1
    duenio=$(stat -c '%u' -- "$ruta") || return 1
    modo=$(stat -c '%a' -- "$ruta") || return 1
    [[ "$duenio" == "0" || "$duenio" == "$(id -u)" ]] || return 1
    # Rechaza binarios modificables por el grupo o por otros (bits 020 y 002).
    (( (8#$modo & 8#022) == 0 ))
}

paquete_de() { # ruta → nombre del paquete dpkg que la instaló (vacío si ninguno)
    dpkg-query -S -- "$1" 2>/dev/null | head -n1 | cut -d: -f1
}

# ---------------------------------------------------------------------------
# Comparación contra la tabla
# ---------------------------------------------------------------------------
evaluar() { # componente versión tabla campos_de_rama detalle es_paquete_ubuntu
    local componente="$1" version="$2" tabla="$3" campos="$4" detalle="$5" es_ubuntu="$6"
    local rama linea ultima nota mas_nueva
    rama=$(cut -d. -f1-"$campos" <<<"$version")
    linea=$(awk -F'|' -v r="$rama" '$1 == r { print; exit }' <<<"$tabla")
    if [[ -z "$linea" ]]; then
        mas_nueva=$(head -n1 <<<"$tabla" | cut -d'|' -f1)
        if dpkg --compare-versions "$rama" gt "$mas_nueva"; then
            informar "AVISO" "$componente $version$detalle: la rama $rama es posterior a la tabla ($TABLA_FECHA) o es preliminar; no se evalúa"
        elif (( es_ubuntu == 1 )); then
            informar "AVISO" "$componente $version$detalle: la rama $rama ya no tiene soporte del proyecto original; Ubuntu mantiene el paquete con parches propios mientras su versión de Ubuntu tenga soporte"
        else
            informar "SIN-SOPORTE" "$componente $version$detalle: la rama $rama ya no recibe correcciones de seguridad"
        fi
        return
    fi
    IFS='|' read -r _ ultima nota <<<"$linea"
    if dpkg --compare-versions "$version" lt "$ultima"; then
        informar "ATENCIÓN" "$componente $version$detalle está desactualizado: la última de la rama $rama es $ultima"
    else
        informar "OK" "$componente $version$detalle (última de la rama $rama: $ultima)"
    fi
    if [[ -n "$nota" ]]; then
        informar "AVISO" "$componente: $nota"
    fi
}

revisar() { # componente tabla campos_de_rama función_de_versión rutas...
    local componente="$1" tabla="$2" campos="$3" extractor="$4"
    shift 4
    local ruta real version detalle pkg pkgver es_ubuntu encontrado=0
    local -A vistas=()
    for ruta in "$@"; do
        [[ -n "$ruta" && -e "$ruta" ]] || continue
        real=$(readlink -f -- "$ruta") || continue
        [[ -n "${vistas[$real]:-}" ]] && continue
        vistas[$real]=1
        encontrado=1
        detalle=" [$real"
        es_ubuntu=0
        if [[ -n "${EN_EJECUCION[$real]:-}" ]]; then
            detalle+=", en ejecución"
        fi
        if se_puede_ejecutar "$real"; then
            version=$("$extractor" "$real")
        else
            version=$(version_desde_ruta "$real")
            if [[ -n "$version" ]]; then
                detalle+=", versión deducida de la ruta"
            else
                informar "AVISO" "$componente [$real]: no evaluado; el binario pertenece a otro usuario o es modificable por otros"
                continue
            fi
        fi
        if [[ -z "$version" ]]; then
            informar "AVISO" "$componente [$real]: no se pudo determinar la versión"
            continue
        fi
        pkg=$(paquete_de "$real")
        if [[ -n "$pkg" ]]; then
            pkgver=$(dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null)
            detalle+=", paquete $pkg $pkgver"
            if [[ "$pkgver" == *ubuntu* ]]; then
                hay_paquetes_ubuntu=1
                es_ubuntu=1
                detalle+=" *"
            fi
        fi
        detalle+="]"
        evaluar "$componente" "$version" "$tabla" "$campos" "$detalle" "$es_ubuntu"
        if [[ -n "$pkg" ]] && grep -qxF -- "$pkg" <<<"$PENDIENTES"; then
            informar "ATENCIÓN" "$componente: el paquete $pkg tiene una actualización pendiente en apt"
        fi
    done
    if (( encontrado == 0 )); then
        informar "INFO" "$componente: no encontrado"
    fi
}

rutas_en_proc() { # patrón glob sobre el nombre del ejecutable
    local r
    for r in "${PROC_RUTAS[@]}"; do
        # shellcheck disable=SC2053  # $1 es un patrón glob a propósito
        [[ "${r##*/}" == $1 ]] && printf '%s\n' "$r"
    done
}

# ---------------------------------------------------------------------------
# Relevamiento del sistema
# ---------------------------------------------------------------------------
relevar_procesos() {
    local dir exe base pid
    for dir in /proc/[0-9]*; do
        exe=$(readlink -- "$dir/exe" 2>/dev/null) || continue
        base=${exe##*/}
        base=${base% (deleted)}
        case "$base" in
            node|nginx|caddy|postgres|php|php[0-9]*|php-fpm*) ;;
            *) continue ;;
        esac
        pid=${dir#/proc/}
        if [[ "$exe" == *" (deleted)" ]]; then
            PROC_REEMPLAZADOS[${exe% (deleted)}]=$pid
        else
            PROC_RUTAS+=("$exe")
            EN_EJECUCION[$(readlink -f -- "$exe")]=1
        fi
    done
}

revisar_ubuntu() {
    local id version linea fin nota mas_nueva
    if [[ ! -r /etc/os-release ]]; then
        informar "AVISO" "Sistema: no se encontró /etc/os-release"
        return
    fi
    id=$(awk -F= '$1 == "ID" { gsub(/"/, "", $2); print $2 }' /etc/os-release)
    version=$(awk -F= '$1 == "VERSION_ID" { gsub(/"/, "", $2); print $2 }' /etc/os-release)
    if [[ "$id" != "ubuntu" ]]; then
        informar "AVISO" "Sistema $id $version: la tabla solo contempla Ubuntu"
        return
    fi
    linea=$(awk -F'|' -v r="$version" '$1 == r { print; exit }' <<<"$TABLA_UBUNTU")
    if [[ -z "$linea" ]]; then
        mas_nueva=$(head -n1 <<<"$TABLA_UBUNTU" | cut -d'|' -f1)
        if dpkg --compare-versions "$version" gt "$mas_nueva"; then
            informar "AVISO" "Ubuntu $version: versión posterior a la tabla ($TABLA_FECHA)"
        else
            informar "SIN-SOPORTE" "Ubuntu $version: sin soporte estándar (las LTS antiguas solo reciben parches mediante Ubuntu Pro/ESM)"
        fi
        return
    fi
    IFS='|' read -r _ fin nota <<<"$linea"
    informar "OK" "Ubuntu $version (soporte estándar hasta $fin)"
    if [[ -n "$nota" ]]; then
        informar "AVISO" "Ubuntu $version: $nota"
    fi
}

revisar_apt() {
    local listado total seguridad dias
    listado=$(apt list --upgradable 2>/dev/null | tail -n +2)
    PENDIENTES=$(cut -d/ -f1 <<<"$listado" | sed '/^$/d')
    total=$(sed '/^$/d' <<<"$listado" | wc -l)
    seguridad=$(grep -c -- '-security' <<<"$listado")
    if (( total > 0 )); then
        informar "ATENCIÓN" "apt: $total actualizaciones pendientes, $seguridad de ellas de seguridad"
    else
        informar "OK" "apt: sin actualizaciones pendientes"
    fi
    if [[ -e /var/cache/apt/pkgcache.bin ]]; then
        dias=$(( ( $(date +%s) - $(stat -c %Y /var/cache/apt/pkgcache.bin) ) / 86400 ))
        if (( dias > 1 )); then
            informar "AVISO" "apt: la información de repositorios tiene $dias días; sin un 'apt update' reciente las actualizaciones pendientes pueden no aparecer"
        fi
    fi
    if [[ -e /var/run/reboot-required ]]; then
        informar "ATENCIÓN" "Sistema: hay un reinicio pendiente (/var/run/reboot-required)"
    fi
}

revisar_reemplazados() {
    local ruta
    for ruta in "${!PROC_REEMPLAZADOS[@]}"; do
        informar "ATENCIÓN" "Proceso ${PROC_REEMPLAZADOS[$ruta]} ejecuta $ruta, binario reemplazado desde que arrancó: sigue corriendo la versión anterior hasta reiniciar el servicio"
    done
}

# ---------------------------------------------------------------------------
# Programa principal
# ---------------------------------------------------------------------------
principal() {
    local -a extra
    printf '%s %s (tabla de versiones al %s)\n' "$NOMBRE" "$VERSION" "$TABLA_FECHA"
    printf 'Equipo: %s — %s\n' "$(hostname)" "$(date '+%Y-%m-%d %H:%M')"
    if (( EUID != 0 )); then
        informar "INFO" "Ejecución sin sudo: no se ven los procesos de otros usuarios"
    fi

    relevar_procesos

    titulo "Sistema"
    revisar_ubuntu
    revisar_apt

    titulo "PHP"
    mapfile -t extra < <(rutas_en_proc 'php*')
    revisar "PHP" "$TABLA_PHP" 2 version_php \
        "$(command -v php || true)" /usr/bin/php[0-9]*.[0-9]* /usr/sbin/php-fpm[0-9]*.[0-9]* "${extra[@]}"

    titulo "nginx"
    mapfile -t extra < <(rutas_en_proc 'nginx')
    revisar "nginx" "$TABLA_NGINX" 2 version_nginx "$(command -v nginx || true)" /usr/sbin/nginx "${extra[@]}"

    titulo "Caddy"
    mapfile -t extra < <(rutas_en_proc 'caddy')
    revisar "Caddy" "$TABLA_CADDY" 2 version_caddy "$(command -v caddy || true)" /usr/bin/caddy "${extra[@]}"

    titulo "PostgreSQL"
    mapfile -t extra < <(rutas_en_proc 'postgres')
    revisar "PostgreSQL" "$TABLA_POSTGRES" 1 version_postgres \
        /usr/lib/postgresql/*/bin/postgres "$(command -v postgres || true)" "${extra[@]}"

    titulo "Node.js"
    mapfile -t extra < <(rutas_en_proc 'node')
    revisar "Node.js" "$TABLA_NODE" 1 version_node \
        "$(command -v node || true)" /usr/bin/node /usr/local/bin/node \
        /opt/.nvm/versions/node/*/bin/node "${NVM_DIR:-/opt/.nvm}"/versions/node/*/bin/node \
        /root/.nvm/versions/node/*/bin/node /home/*/.nvm/versions/node/*/bin/node "${extra[@]}"

    titulo "Procesos en ejecución"
    if (( ${#PROC_REEMPLAZADOS[@]} == 0 )); then
        informar "OK" "Ningún proceso relevado ejecuta un binario reemplazado"
    else
        revisar_reemplazados
    fi

    if (( hay_paquetes_ubuntu == 1 )); then
        printf '\n* Paquete de Ubuntu: Ubuntu aplica parches de seguridad sin cambiar la versión base,\n'
        printf '  así que la comparación con la tabla puede dar falso positivo. Para estos paquetes\n'
        printf '  el indicador confiable es si apt tiene una actualización pendiente.\n'
    fi

    printf '\nObservaciones: %d\n' "$observaciones"
    (( observaciones == 0 ))
}

principal
