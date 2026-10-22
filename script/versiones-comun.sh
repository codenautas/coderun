#!/usr/bin/env bash
# versiones-comun.sh
#
# Biblioteca compartida por revisar-versiones.sh y versiones.sh. Define qué
# productos se relevan, dónde se buscan sus binarios y cómo se obtiene la
# versión de cada uno, para que ambos scripts miren lo mismo de la misma forma.
#
# No se ejecuta por sí sola: se incluye con
#   source "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/versiones-comun.sh"
#
# Al incluirse activa nullglob (los patrones sin coincidencias quedan vacíos),
# que es lo que necesitan las búsquedas de binarios de ambos scripts.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf 'versiones-comun.sh es una biblioteca de revisar-versiones.sh y versiones.sh, no un script ejecutable\n' >&2
    exit 2
fi

shopt -s nullglob

# ---------------------------------------------------------------------------
# Productos relevados, en el orden en que se informan. Formato: id|nombre
# ---------------------------------------------------------------------------
readonly PRODUCTOS='php|PHP
nginx|nginx
apache|Apache httpd
caddy|Caddy
postgres|PostgreSQL
mysql|MySQL
mariadb|MariaDB
node|Node.js'

# ---------------------------------------------------------------------------
# Estado del relevamiento (lo completan relevar_procesos y leer_sistema)
# ---------------------------------------------------------------------------
declare -a PROC_RUTAS=()          # binarios en ejecución (ruta real)
declare -A PROC_PIDS=()           # ruta real → PIDs separados por espacio
declare -A PROC_REEMPLAZADOS=()   # binario reemplazado desde que arrancó → PID
SO_ID=""
SO_VERSION=""
SO_NOMBRE=""

# Resultado de obtener_version
VERSION_ENCONTRADA=""
VERSION_DEDUCIDA=0

# ---------------------------------------------------------------------------
# Identificación de productos
# ---------------------------------------------------------------------------
productos_de_ejecutable() { # nombre de ejecutable → ids de producto separados por espacio (vacío si ninguno)
    case "$1" in
        php|php[0-9]*|php-fpm*|php-cgi*) printf 'php' ;;
        nginx)                           printf 'nginx' ;;
        apache2|httpd)                   printf 'apache' ;;
        caddy)                           printf 'caddy' ;;
        postgres)                        printf 'postgres' ;;
        mysqld|mariadbd)                 printf 'mysql mariadb' ;; # se distinguen por la versión
        node)                            printf 'node' ;;
    esac
}

candidatos() { # id → rutas posibles del binario, una por línea (pueden repetirse o no existir)
    local id="$1" ruta
    case "$id" in
        php)           printf '%s\n' "$(command -v php || true)" /usr/bin/php[0-9]*.[0-9]* /usr/sbin/php-fpm[0-9]*.[0-9]* ;;
        nginx)         printf '%s\n' "$(command -v nginx || true)" /usr/sbin/nginx ;;
        apache)        printf '%s\n' /usr/sbin/apache2 ;;
        caddy)         printf '%s\n' "$(command -v caddy || true)" /usr/bin/caddy ;;
        postgres)      printf '%s\n' /usr/lib/postgresql/*/bin/postgres ;;
        mysql|mariadb) printf '%s\n' /usr/sbin/mysqld /usr/sbin/mariadbd ;;
        node)          printf '%s\n' "$(command -v node || true)" /usr/bin/node /usr/local/bin/node \
                           /opt/.nvm/versions/node/*/bin/node "${NVM_DIR:-/opt/.nvm}"/versions/node/*/bin/node \
                           /root/.nvm/versions/node/*/bin/node /home/*/.nvm/versions/node/*/bin/node ;;
    esac
    for ruta in "${PROC_RUTAS[@]}"; do
        if [[ " $(productos_de_ejecutable "${ruta##*/}") " == *" $id "* ]]; then
            printf '%s\n' "$ruta"
        fi
    done
}

binarios() { # id → rutas reales existentes, sin repetir
    local ruta real
    local -A vistas=()
    while IFS= read -r ruta; do
        [[ -n "$ruta" && -e "$ruta" ]] || continue
        real=$(readlink -f -- "$ruta") || continue
        [[ -z "${vistas[$real]:-}" ]] || continue
        vistas[$real]=1
        printf '%s\n' "$real"
    done < <(candidatos "$1")
}

# ---------------------------------------------------------------------------
# Obtención de versiones
# ---------------------------------------------------------------------------
se_puede_ejecutar() { # ruta
    # Solo se ejecutan binarios de root o del usuario actual que no sean
    # modificables por el grupo ni por otros: ejecutar como root un binario
    # que otro usuario puede reemplazar permitiría escalar privilegios.
    local ruta="$1" duenio modo
    [[ -f "$ruta" && -x "$ruta" ]] || return 1
    duenio=$(stat -c '%u' -- "$ruta") || return 1
    modo=$(stat -c '%a' -- "$ruta") || return 1
    [[ "$duenio" == "0" || "$duenio" == "$(id -u)" ]] || return 1
    (( (8#$modo & 8#022) == 0 ))
}

version_desde_ruta() { # ruta → p. ej. /opt/.nvm/versions/node/v22.2.0/bin/node → 22.2.0
    grep -oE '/v?[0-9]+\.[0-9]+(\.[0-9]+)?/' <<<"$1" | tail -n1 | tr -d '/v'
}

version_informada() { # id ruta → versión que informa el propio binario
    local id="$1" ruta="$2"
    case "$id" in
        php)           timeout 10 "$ruta" -v </dev/null 2>/dev/null | head -n1 | grep -oE '^PHP [0-9]+\.[0-9]+\.[0-9]+' | cut -d' ' -f2 ;;
        nginx)         timeout 10 "$ruta" -v </dev/null 2>&1 | grep -oE 'nginx/[0-9]+\.[0-9]+\.[0-9]+' | head -n1 | cut -d/ -f2 ;;
        apache)        timeout 10 "$ruta" -v </dev/null 2>/dev/null | grep -oE 'Apache/[0-9]+\.[0-9]+\.[0-9]+' | head -n1 | cut -d/ -f2 ;;
        caddy)         timeout 10 "$ruta" version </dev/null 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n1 | cut -c2- ;;
        postgres)      timeout 10 "$ruta" --version </dev/null 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -n1 ;;
        mysql|mariadb) timeout 10 "$ruta" --version </dev/null 2>/dev/null | grep -oE 'Ver [0-9]+\.[0-9]+\.[0-9]+' | head -n1 | cut -d' ' -f2 ;;
        node)          timeout 10 "$ruta" -v </dev/null 2>/dev/null | grep -oE '^v[0-9]+\.[0-9]+\.[0-9]+' | cut -c2- ;;
    esac
}

variante_mysql() { # ruta se_puede_ejecutar(0|1) → mysql | mariadb
    local ruta="$1" ejecutable="$2"
    if [[ "${ruta##*/}" == "mariadbd" ]]; then
        printf 'mariadb'
    elif (( ejecutable == 1 )) && timeout 10 "$ruta" --version </dev/null 2>/dev/null | grep -q 'MariaDB'; then
        printf 'mariadb'
    elif [[ "$(paquete_de "$ruta")" == mariadb* ]]; then
        printf 'mariadb'
    else
        printf 'mysql'
    fi
}

obtener_version() { # id ruta → deja el resultado en VERSION_ENCONTRADA y VERSION_DEDUCIDA
    # Estado: 0 versión obtenida
    #         1 el binario no informó su versión
    #         2 el binario corresponde a otro producto (MySQL y MariaDB comparten nombres)
    #         3 el binario no se ejecutó (ver se_puede_ejecutar) y la ruta no indica la versión
    local id="$1" ruta="$2" ejecutable=0
    VERSION_ENCONTRADA=""
    VERSION_DEDUCIDA=0
    if se_puede_ejecutar "$ruta"; then
        ejecutable=1
    fi
    if [[ "$id" == "mysql" || "$id" == "mariadb" ]]; then
        [[ "$(variante_mysql "$ruta" "$ejecutable")" == "$id" ]] || return 2
    fi
    if (( ejecutable == 1 )); then
        VERSION_ENCONTRADA=$(version_informada "$id" "$ruta")
    else
        VERSION_ENCONTRADA=$(version_desde_ruta "$ruta")
        [[ -n "$VERSION_ENCONTRADA" ]] || return 3
        VERSION_DEDUCIDA=1
    fi
    [[ -n "$VERSION_ENCONTRADA" ]] || return 1
}

# ---------------------------------------------------------------------------
# Paquetes, procesos y sistema
# ---------------------------------------------------------------------------
paquete_de() { # ruta → nombre del paquete dpkg que la instaló (vacío si ninguno)
    dpkg-query -S -- "$1" 2>/dev/null | head -n1 | cut -d: -f1
}

version_de_paquete() { # paquete → versión instalada
    dpkg-query -W -f='${Version}' "$1" 2>/dev/null
}

relevar_procesos() {
    local dir exe base real pid
    for dir in /proc/[0-9]*; do
        exe=$(readlink -- "$dir/exe" 2>/dev/null) || continue
        base=${exe##*/}
        base=${base% (deleted)}
        [[ -n "$(productos_de_ejecutable "$base")" ]] || continue
        pid=${dir#/proc/}
        if [[ "$exe" == *" (deleted)" ]]; then
            PROC_REEMPLAZADOS[${exe% (deleted)}]=$pid
            continue
        fi
        real=$(readlink -f -- "$exe") || continue
        if [[ -z "${PROC_PIDS[$real]:-}" ]]; then
            PROC_RUTAS+=("$real")
            PROC_PIDS[$real]=$pid
        else
            PROC_PIDS[$real]+=" $pid"
        fi
    done
}

leer_sistema() {
    [[ -r /etc/os-release ]] || return 1
    SO_ID=$(awk -F= '$1 == "ID" { gsub(/"/, "", $2); print $2 }' /etc/os-release)
    SO_VERSION=$(awk -F= '$1 == "VERSION_ID" { gsub(/"/, "", $2); print $2 }' /etc/os-release)
    SO_NOMBRE=$(awk -F= '$1 == "PRETTY_NAME" { gsub(/"/, "", $2); print $2 }' /etc/os-release)
}
