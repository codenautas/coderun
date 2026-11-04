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
# No modifica nada salvo con --cambiar o --limpiar --aplicar.
# Ayuda completa con el procedimiento: node-servicios.sh --help

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

ayuda() {
    cat <<'AYUDA'
node-servicios.sh — versiones de node de los servicios de /opt/services

CÓMO FUNCIONA
  El número que sigue a run-app.sh en el .service es la versión de node:
  "run-app.sh 12" hace "nvm use 12" y usa la 12.x más alta instalada en
  /opt/.nvm. Sin número usa el alias default de nvm.
  - Un proceso ya iniciado no cambia de versión: el cambio rige desde el próximo
    reinicio del servicio.
  - Los servicios sin número toman el default cada vez que arrancan. Si se
    sube el default, todos suben en su próximo reinicio.
  - Si la versión fijada no está instalada, "nvm use" falla y "npm start" corre
    con el node que haya en el PATH (el informe la marca NO INSTALADA).

OPCIONES
  (sin opciones)         Informe de solo lectura: por servicio, estado, versión
                         fijada, versión a la que resuelve, versión más alta
                         instalada a la que podría subir y "engines" del
                         package.json. Después, qué servicios usa cada versión
                         instalada.
  --solo-fijadas         Omite los servicios sin versión fijada.
  --dir DIR              Otro directorio de .service (default /opt/services).
  --cambiar SERV VERSION Edita el .service: VERSION es un número (ej. 22) o "-"
                         para quitar la fijación. Deja backup .bak-AAAAMMDD-HHMMSS,
                         hace daemon-reload y muestra el diff. No reinicia salvo
                         con --reiniciar. Requiere sudo.
  --reiniciar            Con --cambiar: reinicia el servicio.
  --limpiar              Lista los comandos "nvm uninstall" de las versiones sin
                         uso. No ejecuta nada.
  --aplicar              Con --limpiar: las desinstala. Requiere sudo.
  -h, --help             Esta ayuda.

LIMITACIÓN IMPORTANTE
  El informe deduce la versión desde la unidad y el default de nvm, NO desde lo
  que está corriendo. Un servicio que arrancó antes de un cambio de default, o
  que no se reinició, puede usar otra versión. Antes de desinstalar, verificar
  siempre con los procesos reales (paso 3 de abajo).

PROCEDIMIENTO: LIMPIAR VERSIONES SIN USO
  1. Informe:
       sudo node-servicios.sh
     Mirar la tabla "Versiones de node instaladas": las "(sin uso)" son
     candidatas.
  2. Servicios caídos o en bucle de reinicios (cada uno debe dar "0 active"):
       for f in /opt/services/*.service; do n=$(basename $f .service)
         echo "$(systemctl show -p NRestarts --value $n) $(systemctl is-active $n) $n"
       done | sort -rn | head -15
  3. Versiones que corren de verdad (solo deben aparecer las que se conservan):
       sudo ls -l /proc/[0-9]*/exe 2>/dev/null | grep -o 'nvm/versions/node/v[0-9.]*' | sort | uniq -c
     Con el servicio de cada una:
       sudo bash -c 'for p in /proc/[0-9]*; do e=$(readlink $p/exe 2>/dev/null)
         case "$e" in *nvm/versions/node/*)
           echo "$(echo $e | grep -o "v[0-9][0-9.]*") $(grep -o "[^/]*\.service" $p/cgroup | head -1)";;
         esac; done | sort -u | sort -V'
     Si una versión "sin uso" aparece acá, NO se borra: hay que reiniciar esos
     servicios para que tomen otra (sudo systemctl restart SERVICIO).
  4. Referencias fuera de /opt/services (cron, otras unidades):
       sudo grep -rl 'nvm/versions/node' /etc/cron* /var/spool/cron /etc/systemd/system 2>/dev/null
     No debe devolver nada.
  5. Simulación:
       sudo node-servicios.sh --limpiar
  6. Borrar una a mano para verificar:
       sudo bash -c '. /opt/.nvm/nvm.sh && nvm uninstall vX.Y.Z'
       ls /opt/.nvm/versions/node/
     Debe decir "Uninstalled node vX.Y.Z" y desaparecer del listado.
  7. Borrar el resto:
       sudo node-servicios.sh --limpiar --aplicar
     Si alguna versión sigue en uso (paso 3), desinstalar a mano solo las demás.
  8. Volver a correr el informe y los chequeos 2 y 3: tienen que quedar solo las
     versiones previstas y los servicios en "active" sin reinicios.
  Una versión borrada se reinstala con: nvm install N

PROCEDIMIENTO: SUBIR LA VERSIÓN DE UN SERVICIO (de a uno, en horario de poco uso)
  1. Cambiar y reiniciar:
       sudo node-servicios.sh --cambiar SERVICIO VERSION --reiniciar
     (VERSION "-" lo deja sin fijar, usando el default de nvm).
  2. Esperar ~30 segundos y verificar:
       systemctl status SERVICIO --no-pager | grep Active
       journalctl -u SERVICIO -n 15 --no-pager | grep -E 'Now using|restart'
     Debe decir "Now using node vX", un "Active" de más de 30 segundos y ningún
     "Scheduled restart job". Probar además una pantalla de la app que use la
     base. Si en el primer minuto aparecen 2 o 3 reinicios y después se
     estabiliza, es el solapamiento con el proceso anterior; esperar antes de
     darlo por malo.
  3. Si falla, volver a la versión anterior:
       sudo node-servicios.sh --cambiar SERVICIO VERSION_ANTERIOR --reiniciar
     o restaurar el backup:
       sudo cp -p /opt/services/SERVICIO.service.bak-FECHA /opt/services/SERVICIO.service
       sudo systemctl daemon-reload && sudo systemctl restart SERVICIO

OTROS CHEQUEOS
  Servicios de /opt/services sin ningún proceso escuchando (esperable en
  tareas como los backups; sospechoso en una app web):
       sudo bash -c 'comm -23 <(ls /opt/services/*.service | xargs -n1 basename | sort) \
         <(ss -ltnpH | grep -o "pid=[0-9]*" | cut -d= -f2 | sort -u | while read p; do grep -o "[^/]*\.service" /proc/$p/cgroup | head -1; done | sort -u)'

PROBLEMAS CONOCIDOS
  - "libatomic.so.1: cannot open shared object file": instalar libatomic1
    (sudo apt install libatomic1). Sin acceso por proxy: "apt download libatomic1"
    o "apt-get install --print-uris -y libatomic1" para ver las URLs de los .deb y
    "sudo dpkg -i" (puede pedir también gcc-XX-base de la misma versión).
  - Al cambiar de versión mayor, los módulos nativos de node_modules pueden
    necesitar recompilarse (buscarlos con: find node_modules -name '*.node').
  - Los backups .bak-* de /opt/services no se limpian solos; borrarlos a mano
    cuando el cambio está confirmado.
  - Si el script falla con "bad interpreter" o "$'\r': command not found" tiene
    finales de línea de Windows: sed -i 's/\r$//' node-servicios.sh
  - Los servicios que no usan run-app.sh no se relevan (se listan aparte): podrían
    usar directamente una versión que figura "sin uso".
AYUDA
}

while (( $# )); do
    case "$1" in
        --dir)         SERVICIOS_DIR=$2; shift 2 ;;
        --solo-fijadas) SOLO_FIJADAS=1; shift ;;
        --cambiar)     CAMBIAR=$2; NUEVA=$3; shift 3 ;;
        --reiniciar)   REINICIAR=1; shift ;;
        --limpiar)     LIMPIAR=1; shift ;;
        --aplicar)     APLICAR=1; shift ;;
        -h|--help)     ayuda; exit 0 ;;
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
printf '\nNota: las versiones se deducen de las unidades y del default de nvm, no de los procesos en ejecución.\n'
printf 'Cambiar uno:  sudo %s --cambiar SERVICIO VERSION [--reiniciar]\n' "$(basename "$0")"
printf 'Procedimiento completo y chequeos: %s --help\n' "$(basename "$0")"
