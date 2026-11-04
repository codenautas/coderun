#!/bin/bash
# Versión no interactiva de deploy-inst.sh, pensada para correr desde CI.
# Uso: deploy-inst-ci.sh <instancia> <tag>
# Si algo falla vuelve al commit anterior y reinicia el servicio.

set -euo pipefail

nombre_dir="${1:-}"
tag="${2:-}"

if [ -z "$nombre_dir" ] || [ -z "$tag" ]; then
    echo "Uso: $0 <instancia> <tag>" >&2
    exit 1
fi

if [[ ! "$tag" =~ ^v[0-9]+\.[0-9]+ ]]; then
    echo "❌ Tag inválido: $tag" >&2
    exit 1
fi

PATH_YAML="/opt/insts/${nombre_dir}.yaml"
[ -f "/opt/bin/bash-yaml/script/yaml.sh" ] || { echo "❌ No se encontró el parser yaml.sh" >&2; exit 1; }
[ -f "$PATH_YAML" ] || { echo "❌ No existe el archivo $PATH_YAML" >&2; exit 1; }
source /opt/bin/bash-yaml/script/yaml.sh
create_variables "$PATH_YAML"

export NVM_DIR="/opt/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

echo "=== Deploy de $nombre_dir ($tag) en $server_base_url ==="

APP_DIR="/opt/npm/$nombre_dir"
cd "$APP_DIR"

restaurar_permisos() {
    sudo chown -R "${server_user}" "$APP_DIR"
}

reiniciar() {
    sudo systemctl daemon-reload
    sudo systemctl restart "$nombre_dir.service"
    sleep 5
    systemctl is-active --quiet "$nombre_dir.service"
}

construir() {
    rm -rf dist
    npm ci
}

sudo chown -R "$USER" .
trap restaurar_permisos EXIT

commit_anterior=$(git rev-parse HEAD)

git fetch origin --tags --force
git rev-parse --verify --quiet "refs/tags/$tag^{commit}" > /dev/null || { echo "❌ No existe el tag $tag" >&2; exit 1; }
git reset --hard "refs/tags/$tag"

if construir && restaurar_permisos && reiniciar; then
    echo "✅ INSTANCIA $nombre_dir ACTUALIZADA A $tag Y ONLINE"
    exit 0
fi

echo "❌ Falló el deploy de $tag. Volviendo a $commit_anterior" >&2
sudo chown -R "$USER" .
git reset --hard "$commit_anterior"
construir || true
restaurar_permisos
reiniciar || echo "⚠️ El servicio no quedó activo tras el rollback. Revisá los logs." >&2
exit 1
