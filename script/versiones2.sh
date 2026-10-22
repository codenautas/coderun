#!/usr/bin/env bash
# versiones.sh
#
# Inventario de los productos instalados: versión, ubicación, paquete, si está
# en ejecución y en qué puertos TCP escucha. Releva los mismos productos que
# revisar-versiones.sh (definidos en versiones-comun.sh) pero no evalúa si
# están actualizados. Sirve para completar la tabla de motores de cada servidor.
#
# Uso:   sudo bash versiones.sh
#        (sin sudo funciona, pero no ve los procesos, los puertos ni los home
#        de otros usuarios)

set -u

readonly NOMBRE="versiones"
readonly VERSION="0.2.0"

# shellcheck source=versiones-comun.sh
source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/versiones-comun.sh"

declare -A PUERTOS=()   # ruta real del binario → puertos TCP en escucha separados por espacio

relevar_puertos() {
    local linea direccion puerto pid real
    command -v ss >/dev/null || return
    while IFS= read -r linea; do
        direccion=$(awk '{ print $4 }' <<<"$linea")
        puerto=${direccion##*:}
        for pid in $(grep -oE 'pid=[0-9]+' <<<"$linea" | cut -d= -f2 | sort -u); do
            real=$(readlink -f -- "/proc/$pid/exe" 2>/dev/null) || continue
            if [[ -z "${PUERTOS[$real]:-}" ]]; then
                PUERTOS[$real]=$puerto
            elif [[ " ${PUERTOS[$real]} " != *" $puerto "* ]]; then
                PUERTOS[$real]+=" $puerto"
            fi
        done
    done < <(ss -ltnp 2>/dev/null | tail -n +2)
}

mostrar() { # nombre versión detalle
    printf '%-13s %-10s %s\n' "$1" "$2" "$3"
}

inventariar_producto() { # id nombre
    local id="$1" nombre="$2"
    local real detalle pkg estado encontrado=0
    while IFS= read -r real; do
        obtener_version "$id" "$real"
        estado=$?
        case "$estado" in
            2) continue ;;
            3) encontrado=1
               mostrar "$nombre" "?" "$real · no se ejecutó: el binario pertenece a otro usuario o es modificable por otros"
               continue ;;
            1) encontrado=1
               mostrar "$nombre" "?" "$real · no informó su versión"
               continue ;;
        esac
        encontrado=1
        detalle="$real"
        if (( VERSION_DEDUCIDA == 1 )); then
            detalle+=" · versión deducida de la ruta"
        fi
        pkg=$(paquete_de "$real")
        if [[ -n "$pkg" ]]; then
            detalle+=" · paquete $pkg $(version_de_paquete "$pkg")"
        fi
        if [[ -n "${PROC_PIDS[$real]:-}" ]]; then
            detalle+=" · en ejecución"
        fi
        if [[ -n "${PUERTOS[$real]:-}" ]]; then
            detalle+=" · puertos ${PUERTOS[$real]}"
        fi
        mostrar "$nombre" "$VERSION_ENCONTRADA" "$detalle"
    done < <(binarios "$id")
    if (( encontrado == 0 )); then
        mostrar "$nombre" "-" "no encontrado"
    fi
}

principal() {
    local id nombre ruta
    printf '%s %s\n' "$NOMBRE" "$VERSION"
    printf 'Equipo: %s — %s\n' "$(hostname)" "$(date '+%Y-%m-%d %H:%M')"
    if leer_sistema; then
        printf 'Sistema: %s (kernel %s)\n' "$SO_NOMBRE" "$(uname -r)"
    else
        printf 'Sistema: no se encontró /etc/os-release (kernel %s)\n' "$(uname -r)"
    fi
    if (( EUID != 0 )); then
        printf 'Ejecución sin sudo: no se ven los procesos, los puertos ni los home de otros usuarios\n'
    fi
    printf '\n'

    relevar_procesos
    relevar_puertos

    while IFS='|' read -r id nombre; do
        inventariar_producto "$id" "$nombre"
    done <<<"$PRODUCTOS"

    if (( ${#PROC_REEMPLAZADOS[@]} > 0 )); then
        printf '\nProcesos que ejecutan un binario reemplazado desde que arrancaron:\n'
        for ruta in "${!PROC_REEMPLAZADOS[@]}"; do
            printf '  PID %s: %s\n' "${PROC_REEMPLAZADOS[$ruta]}" "$ruta"
        done
    fi
}

principal
