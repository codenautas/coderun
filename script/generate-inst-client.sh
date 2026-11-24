#!/bin/bash
# Crea una instancia de una app que es solo cliente (archivos estaticos en dist)
# a partir de /opt/insts/$nombre_dir.yaml (creado por prepare-inst-client.sh).
#
# Clona el repo en /opt/npm/$nombre_dir, enlaza el yaml como local-config.yaml,
# compila (npm ci + npm run build), genera /opt/nginx.conf/$nombre_dir.conf con
# generate-nginx-inst-client.sh y recarga nginx solo si nginx -t da ok.

crear_inst_client() {
    # 1. Identificación de la Instancia
    echo "=== Creación de Instancia Cliente ==="
    # el nombre puede venir como parámetro (lo pasa prepare-inst-client.sh)
    nombre_dir="$1"
    if [ -z "$nombre_dir" ]; then
        read -p "Ingrese el nombre de la instancia (ej. pripc-tools): " nombre_dir
    fi
    if [ -z "$nombre_dir" ]; then
        echo "❌ Error: El nombre no puede estar vacío."
        return 1
    fi
    export nombre_dir

    # 2. Cargar Parser YAML y Variables
    local PATH_YAML="/opt/insts/${nombre_dir}.yaml"
    if [ ! -f "/opt/bin/bash-yaml/script/yaml.sh" ]; then
        echo "❌ Error: No se encontró el parser yaml.sh"
        return 1
    fi
    if [ ! -f "$PATH_YAML" ]; then
        echo "❌ Error: No existe el archivo $PATH_YAML (crearlo con prepare-inst-client.sh)"
        return 1
    fi
    source /opt/bin/bash-yaml/script/yaml.sh
    create_variables "$PATH_YAML"

    # 3. Cargar NVM (Entorno Node)
    export NVM_DIR="/opt/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

    local APP_DIR="/opt/npm/$nombre_dir"
    export url_source=$git_host/$git_group/${git_project}.git
    export nombre_user=$server_user

    # 4. Resumen de Seguridad
    echo -e "\n------------------------------------------"
    echo "🏗️  CREANDO INSTANCIA CLIENTE"
    echo "------------------------------------------"
    echo "📁 Directorio: $APP_DIR"
    echo "📡 Repo:       $url_source"
    echo "🌐 URL:        $server_base_url/"
    echo "📄 Index:      ${server_index:-(no definido en el yaml)}"
    echo "👤 Usuario:    $nombre_user"
    echo "------------------------------------------"
    read -p "¿Confirmar ejecución con privilegios sudo? (s/n): " CONFIRMAR
    [[ "$CONFIRMAR" =~ ^[Ss]$ ]] || { echo "❌ Operación cancelada."; return 0; }

    restaurar_permisos() {
        echo "🛡️ Restaurando permisos de root y usuario app..."
        sudo chown root /opt/npm
        sudo chown -R root /opt/nginx.conf
        if [ -d "$APP_DIR" ] && id -u "$nombre_user" >/dev/null 2>&1; then
            sudo chown -R "$nombre_user" "$APP_DIR"
        fi
    }

    # 5. Usuario del SO
    if id -u "$nombre_user" >/dev/null 2>&1; then
        echo "✅ El usuario $nombre_user ya existe."
    else
        echo "👤 Creando usuario $nombre_user..."
        sudo useradd "$nombre_user" || { echo "❌ No se pudo crear el usuario $nombre_user"; return 1; }
    fi
    sudo adduser "$nombre_user" runner

    # 6. Clonar el repo
    sudo chown $USER /opt/npm
    if [ -d "$APP_DIR/.git" ]; then
        echo "✅ Ya existe $APP_DIR, no se clona."
        sudo chown -R $USER "$APP_DIR"
    elif [ -n "$(ls -A "$APP_DIR" 2>/dev/null)" ]; then
        echo "❌ $APP_DIR existe, no está vacía y no es un repositorio git."
        restaurar_permisos
        return 1
    else
        mkdir -p "$APP_DIR"
        while ! git clone "$url_source" "$APP_DIR"; do
            echo -e "\n❌ Error al clonar $url_source"
            read -p "¿Deseas reintentar la autenticación de Git? (s/n): " REINTENTAR
            if [[ ! "$REINTENTAR" =~ ^[Ss]$ ]]; then
                echo "🛑 Operación cancelada."
                rmdir "$APP_DIR" 2>/dev/null
                restaurar_permisos
                return 1
            fi
        done
        echo "✅ Repo clonado."
    fi
    cd "$APP_DIR" || { echo "❌ No se pudo entrar a $APP_DIR"; restaurar_permisos; return 1; }

    # 7. local-config.yaml -> yaml de la instancia
    if [ ! -e local-config.yaml ]; then
        sudo ln -s "$PATH_YAML" "$APP_DIR/local-config.yaml"
    fi

    # 8. Compilación
    echo "📦 Instalando dependencias (npm ci)..."
    rm -rf dist
    npm ci || { echo "❌ npm ci falló."; restaurar_permisos; return 1; }
    echo "🔨 Compilando (npm run build)..."
    npm run build || { echo "❌ npm run build falló."; restaurar_permisos; return 1; }
    if [ -z "$(ls -A dist 2>/dev/null)" ]; then
        echo "❌ La carpeta dist quedó vacía o no existe."
        restaurar_permisos
        return 1
    fi

    # 9. Configuración de nginx
    echo "🌐 Generando /opt/nginx.conf/${nombre_dir}.conf..."
    sudo chown $USER /opt/nginx.conf
    sudo touch /opt/nginx.conf/${nombre_dir}.conf
    sudo chown $USER /opt/nginx.conf/${nombre_dir}.conf
    . /opt/bin/coderun/script/generate-nginx-inst-client.sh

    restaurar_permisos

    # 10. Validar y recargar nginx (solo si la configuración es válida)
    echo "🔎 Validando configuración de nginx (nginx -t)..."
    if sudo nginx -t; then
        sudo systemctl reload nginx
        echo -e "\n✅ INSTANCIA CLIENTE $nombre_dir CREADA Y PUBLICADA EN $server_base_url/"
    else
        echo -e "\n❌ nginx -t falló: NO se recargó nginx (sigue funcionando con la configuración anterior)."
        echo "   Revisar /opt/nginx.conf/${nombre_dir}.conf y luego correr:"
        echo "   sudo nginx -t && sudo systemctl reload nginx"
        return 1
    fi
}

crear_inst_client "$@"
_rc=$?
return $_rc 2>/dev/null || exit $_rc
