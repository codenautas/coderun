#!/usr/bin/env bash
# node-servicios.sh
#
# Releva los servicios de /opt/services que arrancan con run-app.sh y muestra
# qué versión de node tienen parametrizada (el argumento de run-app.sh, que
# hace `nvm use <versión>`), a qué versión instalada resuelve, y si se puede
# subir según lo que hay instalado en nvm y el "engines" del package.json.
#
# Uso:
#   node-servicios.sh                       # informe (solo lectura)
#   node-servicios.sh --solo-fijadas        # omite los que no tienen versión
#   node-servicios.sh --dir /opt/services   # otro directorio de .service
#   node-servicios.sh --limpiar            # lista las versiones de node sin uso y los
#                                          # comandos para desinstalarlas (no ejecuta)
#   sudo node-servicios.sh --limpiar --aplicar   # las desinstala con nvm
#   sudo node-servicios.sh --cambiar SERVICIO VERSION [--reiniciar]
#       # edita el .service (deja backup .bak-AAAAMMDD-HHMMSS), hace
#       # daemon-reload y, solo con --reiniciar, reinicia el servicio.
#       # VERSION puede ser un número (ej. 20) o "-" para quitar la fijación.
#
# No modifica nada si no se usa --cambiar.

set -u

SERVICIOS_DIR=/opt/services
NVM_DIR=${NVM_DIR:-/opt/.nvm}
NODE_DIR="$NVM_DIR/versions/node"
SOLO_FIJADAS=0
CAMBIAR=""
NUEVA=""
REINICIAR=0
LIMPIAR=0
APLICAR=0

while (( $# )); do
    case "$1" in
        --dir)         SERVICIOS_DIR=$2; shift 2 ;;
        --solo-fijadas) SOLO_FIJADAS=1; shift ;;
        --cambiar)     CAMBIAR=$2; NUEVA=$3; shift 3 ;;
        --reiniciar)   REINICIAR=1; shift ;;
        --limpiar)     LIMPIAR=1; shift ;;
        --aplicar)     APLICAR=1; shift ;;
        -h|--help)     sed -n '2,24p' "$0"; exit 0 ;;
        *) echo "Parámetro desconocido: $1" >&2; exit 2 ;;
    esac
done

# ---- versiones de node instaladas en nvm (ordenadas) ----
mapfile -t INSTALADAS < <(ls -1 "$NODE_DIR" 2>/dev/null | sed 's/^v//' | sort -V)

# mayor versión instalada que cumple el prefijo pedido (como hace nvm use 12 → 12.x.y más alta)
resolver() { # prefijo → versión completa o vacío
    local p=$1 v ult=""
    for v in "${INSTALADAS[@]}"; do
        if [[ "$v" == "$p" || "$v" == "$p".* ]]; then ult=$v; fi
    done
    echo "$ult"
}

mayor_instalada() { # mayor versión en la lista
    [[ ${#INSTALADAS[@]} -gt 0 ]] && echo "${INSTALADAS[-1]}"
}

default_nvm() {
    local a n=0 sig
    a=$(cat "$NVM_DIR/alias/default" 2>/dev/null) || return
    while [[ "$a" == lts/* || "$a" == node || "$a" == stable ]] && (( n++ < 4 )); do
        case "$a" in
            node|stable) mayor_instalada; return ;;
            *) sig=$(cat "$NVM_DIR/alias/$a" 2>/dev/null) || return; a=$sig ;;
        esac
    done
    resolver "${a#v}"
}

# valor ExecStart de run-app.sh → argumento de versión ("" si no tiene)
version_fijada() { # archivo
    local linea
    linea=$(grep -E '^[[:space:]]*ExecStart=.*run-app\.sh' "$1" | head -n1) || return 1
    [[ -n "$linea" ]] || return 1
    # tras run-app.sh, primer token
    sed -E 's/.*run-app\.sh[[:space:]]*([^[:space:]]*).*/\1/' <<<"$linea"
}

usa_run_app() { grep -qE '^[[:space:]]*ExecStart=.*run-app\.sh' "$1"; }

directiva() { # archivo clave
    grep -E "^[[:space:]]*$2=" "$1" | head -n1 | cut -d= -f2-
}

engines_node() { # directorio de trabajo
    local pj="$1/package.json"
    [[ -r "$pj" ]] || { echo "-"; return; }
    if command -v node >/dev/null 2>&1; then
        node -e 'try{const e=(require(process.argv[1]).engines||{}).node;console.log(e||"-")}catch(e){console.log("?")}' "$pj"
    else
        grep -oE '"node"[[:space:]]*:[[:space:]]*"[^"]*"' "$pj" | head -n1 | sed -E 's/.*:[[:space:]]*"([^"]*)"/\1/' || echo "-"
    fi
}

estado() { # nombre servicio
    command -v systemctl >/dev/null 2>&1 || { echo "?"; return; }
    systemctl is-active "$1.service" 2>/dev/null || true
}

# ---- modo cambiar ----
if [[ -n "$CAMBIAR" ]]; then
    f="$SERVICIOS_DIR/${CAMBIAR%.service}.service"
    [[ -w "$f" ]] || { echo "No existe o no se puede escribir: $f (¿falta sudo?)" >&2; exit 1; }
    usa_run_app "$f" || { echo "$f no usa run-app.sh" >&2; exit 1; }
    if [[ "$NUEVA" != "-" ]]; then
        [[ "$NUEVA" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || { echo "Versión inválida: $NUEVA" >&2; exit 1; }
        real=$(resolver "$NUEVA")
        [[ -n "$real" ]] || { echo "node $NUEVA no está instalado en $NODE_DIR (instaladas: ${INSTALADAS[*]})" >&2; exit 1; }
        echo "node $NUEVA resuelve a v$real"
    fi
    bak="$f.bak-$(date +%Y%m%d-%H%M%S)"
    cp -p "$f" "$bak" || exit 1
    sufijo=""; [[ "$NUEVA" != "-" ]] && sufijo=" $NUEVA"
    sed -i -E "s#^([[:space:]]*ExecStart=[^[:space:]]*run-app\.sh)([[:space:]]+[^[:space:]]+)?[[:space:]]*\$#\1$sufijo#" "$f"
    echo "--- diff (backup: $bak)"
    diff "$bak" "$f"
    systemctl daemon-reload && echo "daemon-reload ok"
    if (( REINICIAR )); then
        systemctl restart "${CAMBIAR%.service}.service" && echo "reiniciado"
    else
        echo "No se reinició. Para aplicar: systemctl restart ${CAMBIAR%.service}"
    fi
    exit 0
fi

# ---- informe ----
printf 'Equipo: %s — %s\n' "$(hostname)" "$(date '+%Y-%m-%d %H:%M')"
printf 'node instalados en %s: %s\n' "$NODE_DIR" "${INSTALADAS[*]:-ninguno}"
DEF=$(default_nvm)
printf 'Default de nvm (servicios sin versión): %s\n\n' "${DEF:+v}${DEF:-no determinable}"
MAYOR=$(mayor_instalada)

printf '%-18s %-8s %-9s %-13s %-10s %s\n' SERVICIO ESTADO FIJADA RESUELVE_A SUBIBLE_A ENGINES
otros=()
declare -A USO=()
fijadas=0; sinfijar=0; sinresolver=0

shopt -s nullglob
for f in "$SERVICIOS_DIR"/*.service; do
    nombre=$(basename "$f" .service)
    if ! usa_run_app "$f"; then otros+=("$nombre"); continue; fi
    fij=$(version_fijada "$f")
    wd=$(directiva "$f" WorkingDirectory)
    eng=$(engines_node "${wd:-/nonexistent}")
    est=$(estado "$nombre")
    if [[ -z "$fij" ]]; then
        (( sinfijar++ ))
        [[ -n "$DEF" ]] && USO[$DEF]+=" $nombre"
        (( SOLO_FIJADAS )) && continue
        printf '%-18s %-8s %-9s %-13s %-10s %s\n' "$nombre" "$est" "(default)" "${DEF:+v$DEF}" "-" "$eng"
        continue
    fi
    (( fijadas++ ))
    res=$(resolver "${fij#v}")
    if [[ -z "$res" ]]; then
        (( sinresolver++ ))
        printf '%-18s %-8s %-9s %-13s %-10s %s\n' "$nombre" "$est" "$fij" "NO INSTALADA" "${MAYOR:+v$MAYOR}" "$eng"
        continue
    fi
    USO[$res]+=" $nombre"
    mayor_fijada=${res%%.*}
    subir="-"
    [[ -n "$MAYOR" && "${MAYOR%%.*}" -gt "$mayor_fijada" ]] && subir="v$MAYOR"
    printf '%-18s %-8s %-9s %-13s %-10s %s\n' "$nombre" "$est" "$fij" "v$res" "$subir" "$eng"
done

printf '\nResumen: %d con versión fijada, %d sin versión (usan default de nvm)' "$fijadas" "$sinfijar"
(( sinresolver )) && printf ', %d con versión fijada NO instalada (nvm use falla y npm start corre con el node que haya en PATH)' "$sinresolver"
printf '\n'
if (( ${#otros[@]} )); then
    printf 'Servicios que no arrancan con run-app.sh (no relevados): %s\n' "${otros[*]}"
fi

# ---- uso de cada versión instalada ----
printf '\nVersiones de node instaladas:\n'
printf '%-12s %s\n' VERSION USADA_POR
SINUSO=()
for v in "${INSTALADAS[@]}"; do
    if [[ -n "${USO[$v]:-}" ]]; then
        printf '%-12s %s\n' "v$v" "${USO[$v]# }"
    else
        SINUSO+=("$v")
        printf '%-12s %s\n' "v$v" "(sin uso)"
    fi
done
if (( ${#otros[@]} )); then
    printf '\nOjo: los servicios no relevados (arriba) podrían usar alguna versión "sin uso" directamente.\n'
fi

if (( LIMPIAR )); then
    printf '\n'
    if (( ${#SINUSO[@]} == 0 )); then
        echo "No hay versiones sin uso para desinstalar."
    else
        for v in "${SINUSO[@]}"; do
            if (( APLICAR )); then
                echo "Desinstalando v$v ..."
                ( export NVM_DIR; . "$NVM_DIR/nvm.sh" && nvm uninstall "v$v" )
            else
                echo "nvm uninstall v$v"
            fi
        done
        (( APLICAR )) || echo "(simulación: agregar --aplicar para ejecutarlo, con el usuario dueño de $NVM_DIR)"
    fi
fi
printf '\nCambiar uno:  sudo %s --cambiar SERVICIO VERSION [--reiniciar]\n' "$(basename "$0")"
