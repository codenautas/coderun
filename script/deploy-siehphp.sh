#!/bin/bash
# deploy-siehphp.sh
# Clona siehphp trayendo solo la carpeta del operativo y las carpetas compartidas que usa.
# Pregunta el ambiente y en qué ruta descargar (Enter = directorio actual) y crea:
#   test       -> <ruta>/<operativo>-test/
#   capa       -> <ruta>/<operativo>-capa/
#   produccion -> <ruta>/<operativo>/
# Uso:
#   bash deploy-siehphp.sh etoi264
#   bash deploy-siehphp.sh etoi264 otra_rama
#   bash deploy-siehphp.sh                    (pide nombre y rama)

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

echo "Ambiente:"
echo "  1) test        -> $OPERATIVO-test"
echo "  2) capa        -> $OPERATIVO-capa"
echo "  3) produccion  -> $OPERATIVO"
while true; do
    read -rp "Elegí el ambiente [1]: " AMBIENTE
    case "${AMBIENTE:-1}" in
        1|test)       AMBIENTE="test";       SUFIJO="-test"; break ;;
        2|capa)       AMBIENTE="capa";       SUFIJO="-capa"; break ;;
        3|produccion) AMBIENTE="produccion"; SUFIJO="";      break ;;
        *) echo "Opción inválida." ;;
    esac
done

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
# La carpeta del operativo adentro del repo siempre se llama $OPERATIVO;
# el sufijo del ambiente va solo en la carpeta del clon.
DESTINO="$BASE/$OPERATIVO$SUFIJO"

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
    read -rp "¿Correr ahora 'bash crear_configuracion.sh $OPERATIVO $AMBIENTE'? [S/n]: " RESP
    case "$RESP" in
        [nN]*) ;;
        *) bash crear_configuracion.sh "$OPERATIVO" "$AMBIENTE" ;;
    esac
else
    echo "Aviso: no se encontró crear_configuracion.sh en $DESTINO." >&2
fi

# ── Dueño www-data, grupo del usuario ────────────────────────────────────────

# Va al final porque crear_configuracion.sh también toca dueños y grupos.
# PHP (www-data) queda como dueño y el usuario sigue pudiendo usar git por el grupo.
GRUPO="$(id -gn)"
echo ""
echo "Ajustando permisos: dueño www-data, grupo $GRUPO ..."
# Que git cree sus archivos nuevos con escritura para el grupo
git config core.sharedRepository group
sudo chown -R "www-data:$GRUPO" "$DESTINO"
sudo chmod -R g+rwX "$DESTINO"
# setgid en las carpetas: lo que se cree adentro hereda el grupo
sudo find "$DESTINO" -type d -exec chmod g+s {} +
# Sin esto git rechaza el repo por ser de otro dueño ("dubious ownership")
if ! git config --global --get-all safe.directory | grep -qxF "$DESTINO"; then
    git config --global --add safe.directory "$DESTINO"
fi

# Un script no puede cambiar el directorio de la terminal que lo llamó;
# se abre una terminal nueva ya parada en el operativo (salir con 'exit').
echo ""
echo "Abriendo una terminal en $DESTINO (escribí 'exit' para volver)."
exec "${SHELL:-bash}"
