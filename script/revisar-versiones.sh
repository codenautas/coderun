#!/usr/bin/env bash
# revisar-versiones.sh
#
# Compara las versiones instaladas de Ubuntu y de los productos definidos en
# versiones-comun.sh contra una tabla fija de versiones vigentes al 2026-10-22.
# versiones.sh releva los mismos productos y muestra el inventario (versión,
# paquete, puertos) sin evaluar si están actualizados.
#
# Uso:   sudo bash revisar-versiones.sh
#        (sin sudo funciona, pero no ve los procesos ni los home de otros usuarios)
#
# Limitaciones conocidas:
# - La tabla es fija: con el paso del tiempo las "últimas versiones" envejecen.
# - Ubuntu aplica parches de seguridad sin cambiar la versión base del paquete.
#   Para esos paquetes (marcados con *) el indicador confiable es si apt tiene
#   una actualización pendiente, no la comparación con la tabla.
# - Por seguridad, solo ejecuta binarios que pertenecen a root o al usuario
#   actual y que no son modificables por el grupo ni por otros usuarios.
#   Para los demás intenta deducir la versión a partir de la ruta (caso nvm).
#
# Código de salida: 0 sin observaciones; 1 con al menos una observación.

set -u

readonly NOMBRE="revisar-versiones"
readonly VERSION="0.2.0"
readonly TABLA_FECHA="2026-10-22"

# shellcheck source=versiones-comun.sh
source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/versiones-comun.sh"

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

readonly TABLA_APACHE='2.4|2.4.69|'

readonly TABLA_CADDY='2.11|2.11.7|'

readonly TABLA_POSTGRES='18|18.6|
17|17.11|
16|16.15|
15|15.19|
14|14.24|la rama 14 deja de recibir correcciones el 2026-11-12'

readonly TABLA_MYSQL='26.10|26.10.0|rama de innovación: deja de recibir correcciones cuando sale la siguiente; para servidores conviene una rama LTS (9.7 u 8.4)
9.7|9.7.4|
8.4|8.4.13|'

readonly TABLA_MARIADB='12.3|12.3.3|
11.8|11.8.9|
11.4|11.4.13|
10.11|10.11.19|'

readonly TABLA_NODE='26|26.12.1|
24|24.22.1|
22|22.23.4|'

# Formato: versión|fin del soporte estándar|observación
readonly TABLA_UBUNTU='26.10|2027-07|
26.04|2031-04|
24.04|2029-04|
22.04|2027-04|quedan menos de seis meses de soporte estándar'

tabla_de() { # id de producto → tabla de versiones
    case "$1" in
        php)      printf '%s' "$TABLA_PHP" ;;
        nginx)    printf '%s' "$TABLA_NGINX" ;;
        apache)   printf '%s' "$TABLA_APACHE" ;;
        caddy)    printf '%s' "$TABLA_CADDY" ;;
        postgres) printf '%s' "$TABLA_POSTGRES" ;;
        mysql)    printf '%s' "$TABLA_MYSQL" ;;
        mariadb)  printf '%s' "$TABLA_MARIADB" ;;
        node)     printf '%s' "$TABLA_NODE" ;;
    esac
}

campos_de_rama() { # id de producto → cantidad de componentes de la versión que forman la rama
    case "$1" in
        postgres|node) printf '1' ;;
        *)             printf '2' ;;
    esac
}

# ---------------------------------------------------------------------------
# Estado global
# ---------------------------------------------------------------------------
observaciones=0
hay_paquetes_ubuntu=0
PENDIENTES=""

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
# Comparación contra la tabla
# ---------------------------------------------------------------------------
evaluar() { # nombre versión tabla campos_de_rama detalle es_paquete_ubuntu
    local nombre="$1" version="$2" tabla="$3" campos="$4" detalle="$5" es_ubuntu="$6"
    local rama linea ultima nota mas_nueva
    rama=$(cut -d. -f1-"$campos" <<<"$version")
    linea=$(awk -F'|' -v r="$rama" '$1 == r { print; exit }' <<<"$tabla")
    if [[ -z "$linea" ]]; then
        mas_nueva=$(head -n1 <<<"$tabla" | cut -d'|' -f1)
        if dpkg --compare-versions "$rama" gt "$mas_nueva"; then
            informar "AVISO" "$nombre $version$detalle: la rama $rama es posterior a la tabla ($TABLA_FECHA) o es preliminar; no se evalúa"
        elif (( es_ubuntu == 1 )); then
            informar "AVISO" "$nombre $version$detalle: la rama $rama ya no tiene soporte del proyecto original; Ubuntu mantiene el paquete con parches propios mientras su versión de Ubuntu tenga soporte"
        else
            informar "SIN-SOPORTE" "$nombre $version$detalle: la rama $rama ya no recibe correcciones de seguridad"
        fi
        return
    fi
    IFS='|' read -r _ ultima nota <<<"$linea"
    if dpkg --compare-versions "$version" lt "$ultima"; then
        informar "ATENCIÓN" "$nombre $version$detalle está desactualizado: la última de la rama $rama es $ultima"
    else
        informar "OK" "$nombre $version$detalle (última de la rama $rama: $ultima)"
    fi
    if [[ -n "$nota" ]]; then
        informar "AVISO" "$nombre: $nota"
    fi
}

revisar_producto() { # id nombre
    local id="$1" nombre="$2"
    local tabla campos real detalle pkg pkgver es_ubuntu estado encontrado=0
    tabla=$(tabla_de "$id")
    campos=$(campos_de_rama "$id")
    while IFS= read -r real; do
        obtener_version "$id" "$real"
        estado=$?
        case "$estado" in
            2) continue ;;
            3) encontrado=1
               informar "AVISO" "$nombre [$real]: no evaluado; el binario pertenece a otro usuario o es modificable por otros"
               continue ;;
            1) encontrado=1
               informar "AVISO" "$nombre [$real]: no se pudo determinar la versión"
               continue ;;
        esac
        encontrado=1
        es_ubuntu=0
        detalle=" [$real"
        if (( VERSION_DEDUCIDA == 1 )); then
            detalle+=", versión deducida de la ruta"
        fi
        if [[ -n "${PROC_PIDS[$real]:-}" ]]; then
            detalle+=", en ejecución"
        fi
        pkg=$(paquete_de "$real")
        if [[ -n "$pkg" ]]; then
            pkgver=$(version_de_paquete "$pkg")
            detalle+=", paquete $pkg $pkgver"
            if [[ "$pkgver" == *ubuntu* ]]; then
                hay_paquetes_ubuntu=1
                es_ubuntu=1
                detalle+=" *"
            fi
        fi
        detalle+="]"
        evaluar "$nombre" "$VERSION_ENCONTRADA" "$tabla" "$campos" "$detalle" "$es_ubuntu"
        if [[ -n "$pkg" ]] && grep -qxF -- "$pkg" <<<"$PENDIENTES"; then
            informar "ATENCIÓN" "$nombre: el paquete $pkg tiene una actualización pendiente en apt"
        fi
    done < <(binarios "$id")
    if (( encontrado == 0 )); then
        informar "INFO" "$nombre: no encontrado"
    fi
}

# ---------------------------------------------------------------------------
# Sistema
# ---------------------------------------------------------------------------
revisar_ubuntu() {
    local linea fin nota mas_nueva
    if ! leer_sistema; then
        informar "AVISO" "Sistema: no se encontró /etc/os-release"
        return
    fi
    if [[ "$SO_ID" != "ubuntu" ]]; then
        informar "AVISO" "Sistema $SO_NOMBRE: la tabla solo contempla Ubuntu"
        return
    fi
    linea=$(awk -F'|' -v r="$SO_VERSION" '$1 == r { print; exit }' <<<"$TABLA_UBUNTU")
    if [[ -z "$linea" ]]; then
        mas_nueva=$(head -n1 <<<"$TABLA_UBUNTU" | cut -d'|' -f1)
        if dpkg --compare-versions "$SO_VERSION" gt "$mas_nueva"; then
            informar "AVISO" "$SO_NOMBRE: versión posterior a la tabla ($TABLA_FECHA)"
        else
            informar "SIN-SOPORTE" "$SO_NOMBRE: sin soporte estándar (las LTS antiguas solo reciben parches mediante Ubuntu Pro/ESM)"
        fi
        return
    fi
    IFS='|' read -r _ fin nota <<<"$linea"
    informar "OK" "$SO_NOMBRE (soporte estándar de la $SO_VERSION hasta $fin)"
    if [[ -n "$nota" ]]; then
        informar "AVISO" "Ubuntu $SO_VERSION: $nota"
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
    if (( ${#PROC_REEMPLAZADOS[@]} == 0 )); then
        informar "OK" "Ningún proceso relevado ejecuta un binario reemplazado"
        return
    fi
    for ruta in "${!PROC_REEMPLAZADOS[@]}"; do
        informar "ATENCIÓN" "Proceso ${PROC_REEMPLAZADOS[$ruta]} ejecuta $ruta, binario reemplazado desde que arrancó: sigue corriendo la versión anterior hasta reiniciar el servicio"
    done
}

# ---------------------------------------------------------------------------
# Programa principal
# ---------------------------------------------------------------------------
principal() {
    local id nombre
    printf '%s %s (tabla de versiones al %s)\n' "$NOMBRE" "$VERSION" "$TABLA_FECHA"
    printf 'Equipo: %s — %s\n' "$(hostname)" "$(date '+%Y-%m-%d %H:%M')"
    if (( EUID != 0 )); then
        informar "INFO" "Ejecución sin sudo: no se ven los procesos ni los home de otros usuarios"
    fi

    relevar_procesos

    titulo "Sistema"
    revisar_ubuntu
    revisar_apt

    while IFS='|' read -r id nombre; do
        titulo "$nombre"
        revisar_producto "$id" "$nombre"
    done <<<"$PRODUCTOS"

    titulo "Procesos en ejecución"
    revisar_reemplazados

    if (( hay_paquetes_ubuntu == 1 )); then
        printf '\n* Paquete de Ubuntu: Ubuntu aplica parches de seguridad sin cambiar la versión base,\n'
        printf '  así que la comparación con la tabla puede dar falso positivo. Para estos paquetes\n'
        printf '  el indicador confiable es si apt tiene una actualización pendiente.\n'
    fi

    printf '\nObservaciones: %d\n' "$observaciones"
    (( observaciones == 0 ))
}

principal
