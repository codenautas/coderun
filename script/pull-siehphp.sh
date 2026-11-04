#!/bin/bash
# pull-siehphp.sh
# Actualiza (git pull) un operativo de siehphp bajado con deploy-siehphp.sh y
# vuelve a dejar los permisos igual: dueño www-data, grupo del usuario.
# Uso:
#   bash pull-siehphp.sh                      (usa el directorio actual)
#   bash pull-siehphp.sh /var/www/etoi264_test

set -e

DIR="${1:-$PWD}"

if [ ! -d "$DIR" ]; then
    echo "Error: no existe '$DIR'." >&2
    exit 1
fi

cd "$DIR"

if ! DESTINO="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    echo "Error: '$DIR' no es un repositorio git." >&2
    exit 1
fi

cd "$DESTINO"

# Sin esto git rechaza el repo por ser de otro dueño ("dubious ownership")
if ! git config --global --get-all safe.directory | grep -qxF "$DESTINO"; then
    git config --global --add safe.directory "$DESTINO"
fi

# ── Pull ─────────────────────────────────────────────────────────────────────

RAMA="$(git rev-parse --abbrev-ref HEAD)"
echo "Actualizando $DESTINO (rama $RAMA) ..."
git pull --ff-only

# ── Dueño www-data, grupo del usuario ────────────────────────────────────────

# Lo que bajó el pull queda a nombre del usuario; se lo devuelve a www-data.
GRUPO="$(id -gn)"
echo ""
echo "Ajustando permisos: dueño www-data, grupo $GRUPO ..."
git config core.sharedRepository group
sudo chown -R "www-data:$GRUPO" "$DESTINO"
sudo chmod -R g+rwX "$DESTINO"
# setgid en las carpetas: lo que se cree adentro hereda el grupo
sudo find "$DESTINO" -type d -exec chmod g+s {} +

echo ""
echo "Listo."
