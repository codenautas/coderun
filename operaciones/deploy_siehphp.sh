#!/bin/bash
# descargar_operativo.sh
# Clona siehphp trayendo solo la carpeta del operativo y las carpetas compartidas que usa.
# Pregunta en qué ruta descargar (Enter = directorio actual) y crea <ruta>/<operativo>/.
# Uso:
#   bash descargar_operativo.sh etoi264
#   bash descargar_operativo.sh etoi264 otra_rama
#   bash descargar_operativo.sh                    (pide nombre y rama)

set -e

REPO_URL="https://github.com/es-ba/siehphp.git"
RAMA_DEF="master"
COMPARTIDAS="tedede encuestas tercera imagenes tools"

OPERATIVO="${1:-}"
RAMA="${2:-}"

if [ -z "$OPERATIVO" ]; then
    read -rp "Nombre del operativo: " OPERATIVO
fi

if [ -z "$OPERATIVO" ]; then
    echo "Error: nombre de operativo vacío." >&2
    exit 1
fi

if [ -z "$RAMA" ]; then
    read -rp "Rama a descargar [$RAMA_DEF]: " RAMA
    RAMA="${RAMA:-$RAMA_DEF}"
fi

read -rp "Ruta donde descargar [$PWD]: " BASE
BASE="${BASE:-$PWD}"
BASE="${BASE/#\~/$HOME}"

if [ ! -d "$BASE" ]; then
    read -rp "No existe '$BASE'. ¿Crearla? [s/N]: " RESP
    case "$RESP" in
        [sS]*) mkdir -p "$BASE" 2>/dev/null || sudo mkdir -p "$BASE" ;;
        *) echo "Cancelado." >&2; exit 1 ;;
    esac
fi

BASE="$(cd "$BASE" && pwd)"
DESTINO="$BASE/$OPERATIVO"

if [ -e "$DESTINO" ]; then
    echo "Error: ya existe '$DESTINO'." >&2
    exit 1
fi

# Si no hay permiso de escritura en la ruta, se crea la carpeta con sudo y se la
# pasa al usuario actual, así el clone (y los git posteriores) no necesitan sudo.
SUDO=""
if [ ! -w "$BASE" ]; then
    echo "Sin permiso de escritura en '$BASE'; se crea '$DESTINO' con sudo."
    SUDO="sudo"
    sudo mkdir "$DESTINO"
    sudo chown "$(id -u):$(id -g)" "$DESTINO"
fi

# ── Clonar sin bajar contenido todavía ───────────────────────────────────────

echo "Clonando $REPO_URL (rama $RAMA) en $DESTINO ..."
git clone --filter=blob:none --sparse --branch "$RAMA" "$REPO_URL" "$DESTINO"
cd "$DESTINO"

if [ -z "$(git ls-tree -d --name-only HEAD -- "$OPERATIVO")" ]; then
    echo "Error: el operativo '$OPERATIVO' no existe en la rama $RAMA." >&2
    cd "$BASE"
    $SUDO rm -rf "$DESTINO"
    exit 1
fi

# ── Bajar solo las carpetas necesarias ───────────────────────────────────────

# shellcheck disable=SC2086
git sparse-checkout set "$OPERATIVO" $COMPARTIDAS

echo ""
echo "Descargado en $DESTINO:"
echo "  $OPERATIVO/ $COMPARTIDAS (+ archivos de la raíz)"
echo ""
echo "Para sumar otra carpeta más adelante:"
echo "  git sparse-checkout add <carpeta>"
echo ""

# ── Siguiente paso: crear la configuración ───────────────────────────────────

if [ -f crear_configuracion.sh ]; then
    read -rp "¿Correr ahora 'bash crear_configuracion.sh $OPERATIVO'? [S/n]: " RESP
    case "$RESP" in
        [nN]*) ;;
        *) bash crear_configuracion.sh "$OPERATIVO" ;;
    esac
else
    echo "Aviso: no se encontró crear_configuracion.sh en $DESTINO." >&2
fi

# Un script no puede cambiar el directorio de la terminal que lo llamó;
# se abre una terminal nueva ya parada en el operativo (salir con 'exit').
echo ""
echo "Abriendo una terminal en $DESTINO (escribí 'exit' para volver)."
exec "${SHELL:-bash}"
