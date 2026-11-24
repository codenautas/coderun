#!/bin/bash
# Actualiza una instancia de una app que es solo cliente (archivos estaticos en dist).
# Version cliente de deploy-inst.sh: baja los cambios de git y recompila.
# No hay servicio que reiniciar ni hace falta recargar nginx: nginx sirve
# directamente los archivos de /opt/npm/$nombre_dir/dist.
# La instancia se crea antes con prepare-inst-client.sh + generate-inst-client.sh

deploy_inst_client() {
    # 1. Identificación de la Instancia
    echo "=== Despliegue de Instancia Cliente ==="
    read -p "Ingrese el nombre de la instancia (ej. pripc-tools): " nombre_dir
    if [ -z "$nombre_dir" ]; then
        echo "❌ Error: El nombre no puede estar vacío."
        return 1
    fi

    # 2. Cargar Parser YAML y Variables
    local PATH_YAML="/opt/insts/${nombre_dir}.yaml"
    if [ ! -f "/opt/bin/bash-yaml/script/yaml.sh" ]; then
        echo "❌ Error: No se encontró el parser yaml.sh"
        return 1
    fi
    if [ ! -f "$PATH_YAML" ]; then
        echo "❌ Error: No existe el archivo $PATH_YAML"
        return 1
    fi
    source /opt/bin/bash-yaml/script/yaml.sh
    create_variables "$PATH_YAML"

    local APP_DIR="/opt/npm/$nombre_dir"
    if [ ! -d "$APP_DIR/.git" ]; then
        echo "❌ Error: No existe $APP_DIR (crear la instancia con generate-inst-client.sh)"
        return 1
    fi

    # 3. Cargar NVM (Entorno Node)
    export NVM_DIR="/opt/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

    # 4. Resumen de Seguridad
    echo -e "\n------------------------------------------"
    echo "🚀 PREPARANDO DEPLOY (solo cliente)"
    echo "------------------------------------------"
    echo "📁 Directorio: $APP_DIR"
    echo "🌐 URL:        $server_base_url/"
    echo "👤 Usuario:    $server_user"
    echo "📌 Versión:    $(git -C "$APP_DIR" log -1 --format='%h %s (%cr)' 2>/dev/null)"
    echo "------------------------------------------"
    read -p "¿Confirmar ejecución con privilegios sudo? (s/n): " CONFIRMAR
    [[ "$CONFIRMAR" =~ ^[Ss]$ ]] || { echo "❌ Operación cancelada."; return 0; }

    restaurar_permisos() {
        echo "🛡️ Restaurando permisos del directorio..."
        sudo chown -R "${server_user}" "$APP_DIR"
    }

    # 5. Actualización de Código con Reintento
    cd "$APP_DIR" || { echo "❌ No se pudo entrar a la carpeta de la app"; return 1; }
    echo "📡 Asignando permisos temporales para Git..."
    sudo chown -R $USER .
    local commit_anterior
    commit_anterior=$(git rev-parse HEAD)

    while true; do
        echo "📡 Sincronizando con Git (Fetch & Reset)..."
        if git fetch origin; then
            local CURRENT_BRANCH
            CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
            git reset --hard "origin/$CURRENT_BRANCH"
            echo "✅ Código sincronizado correctamente."
            break
        fi
        echo -e "\n❌ Error al autenticar o sincronizar con Git."
        read -p "¿Deseas reintentar la autenticación de Git? (s/n): " REINTENTAR
        if [[ ! "$REINTENTAR" =~ ^[Ss]$ ]]; then
            echo "🛑 Operación cancelada por el usuario."
            restaurar_permisos
            return 1
        fi
    done

    if [ "$(git rev-parse HEAD)" = "$commit_anterior" ]; then
        echo "ℹ️  No hay cambios nuevos en git (se recompila igual)."
    else
        echo "📝 Cambios bajados:"
        git log --oneline "$commit_anterior..HEAD"
    fi

    # 6. Reconstrucción
    echo "📦 Reinstalando dependencias (npm ci)..."
    rm -rf dist
    npm ci || { echo "❌ npm ci falló."; restaurar_permisos; return 1; }
    echo "🔨 Compilando (npm run build)..."
    npm run build || { echo "❌ npm run build falló."; restaurar_permisos; return 1; }
    if [ -z "$(ls -A dist 2>/dev/null)" ]; then
        echo "❌ La carpeta dist quedó vacía o no existe."
        restaurar_permisos
        return 1
    fi
    if [ -n "$server_index" ] && [ ! -f "dist/$server_index" ]; then
        echo "⚠️  No existe dist/$server_index (es el index que usa nginx según el yaml)."
    fi

    # 7. Permisos
    restaurar_permisos

    echo -e "\n✅ INSTANCIA CLIENTE $nombre_dir ACTUALIZADA"
    echo "📌 Versión: $(git log -1 --format='%h %s')"
}

deploy_inst_client
_rc=$?
return $_rc 2>/dev/null || exit $_rc
