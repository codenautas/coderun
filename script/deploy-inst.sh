#!/bin/bash

# 1. Identificación de la Instancia
echo "=== Despliegue de Instancia ==="
read -p "Ingrese el nombre de la instancia (ej. prrepsic252): " nombre_dir

if [ -z "$nombre_dir" ]; then
    echo "❌ Error: El nombre no puede estar vacío."
    return 1 2>/dev/null || exit 1
fi

PATH_YAML="/opt/insts/${nombre_dir}.yaml"

# 2. Cargar Parser YAML y Variables
if [ -f "/opt/bin/bash-yaml/script/yaml.sh" ]; then
    source /opt/bin/bash-yaml/script/yaml.sh
    # Validamos que el archivo yaml exista
    if [ ! -f "$PATH_YAML" ]; then
        echo "❌ Error: No existe el archivo $PATH_YAML"
        return 1 2>/dev/null || exit 1
    fi
    create_variables "$PATH_YAML"
else
    echo "❌ Error: No se encontró el parser yaml.sh"
    return 1 2>/dev/null || exit 1
fi

# 3. Cargar NVM (Entorno Node)
export NVM_DIR="/opt/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

# 4. Resumen de Seguridad
echo -e "\n------------------------------------------"
echo "🚀 PREPARANDO DEPLOY"
echo "------------------------------------------"
echo "📁 Directorio: /opt/npm/$nombre_dir"
echo "🌐 URL:        $server_base_url"
echo "👤 Usuario:     $server_user"
echo "------------------------------------------"

read -p "¿Confirmar ejecución con privilegios sudo? (s/n): " CONFIRMAR
[[ "$CONFIRMAR" =~ ^[Ss]$ ]] || { echo "❌ Operación cancelada."; return 0 2>/dev/null || exit 0; }

# 5. Actualización de Código con Reintento y Manejo de Errores
cd "/opt/npm/$nombre_dir/" || { echo "❌ No se pudo entrar a la carpeta de la app"; return 1; }

echo "📡 Asignando permisos temporales para Git..."
sudo chown -R $USER .

while true; do
    echo "📡 Sincronizando con Git (Fetch & Reset)..."
    if git fetch origin; then
        CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
        git reset --hard "origin/$CURRENT_BRANCH"
        echo "✅ Código sincronizado correctamente."
        break # Sale del bucle y continúa el deploy
    else
        echo -e "\n❌ Error al autenticar o sincronizar con Git."
        read -p "¿Deseas reintentar la autenticación de Git? (s/n): " REINTENTAR
        if [[ ! "$REINTENTAR" =~ ^[Ss]$ ]]; then
            echo "🛑 Operación cancelada por el usuario. Restaurando permisos del directorio..."
            sudo chown -R ${server_user} "/opt/npm/$nombre_dir"
            return 1 2>/dev/null || exit 1
        fi
    fi
done

# 6. Reconstrucción
echo "📦 Reinstalando dependencias (npm ci)..."
rm -rf dist
if ! npm ci; then
    echo "❌ npm ci falló. No se reinicia el servicio. Restaurando permisos del directorio..."
    sudo chown -R ${server_user} "/opt/npm/$nombre_dir"
    return 1 2>/dev/null || exit 1
fi

# 7. Permisos de Sistema
echo "🛡️ Restaurando permisos de root y usuario app..."
sudo chown root /opt/npm
sudo chown -R root /opt/nginx.conf
sudo chown -R root /opt/services
sudo chown -R root /opt/bin
sudo chmod +x /opt/bin/coderun/script/run-app.sh
sudo chown -R ${server_user} "/opt/npm/$nombre_dir"

# 8. Reinicio de Servicio
echo "⚙️ Reiniciando $nombre_dir.service..."
sudo systemctl daemon-reload
sudo systemctl restart "$nombre_dir.service"

# 9. Verificación Final
# systemd da por "active" a un servicio Type=simple apenas lanza el proceso,
# aunque la app muera un segundo después. Se espera a que el puerto responda
# y se confirma que el servicio sigue activo y sin reinicios automáticos.
verificar_servicio() { # servicio puerto [limite_seg]
    local svc="$1" port="$2" limite="${3:-60}" t=0 n_antes n_ahora
    n_antes=$(systemctl show -p NRestarts --value "$svc")
    while (( t < limite )); do
        if systemctl is-active --quiet "$svc" && (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
            sleep 5   # confirma que no se cae apenas levanta
            n_ahora=$(systemctl show -p NRestarts --value "$svc")
            systemctl is-active --quiet "$svc" && [ "$n_ahora" = "$n_antes" ] && return 0
            return 1
        fi
        sleep 2; t=$((t+2))
    done
    return 1
}

echo "🔎 Verificando que $nombre_dir.service responda en el puerto $server_port..."
if verificar_servicio "$nombre_dir.service" "$server_port"; then
    echo -e "\n✅ INSTANCIA $nombre_dir ACTUALIZADA Y ONLINE"
else
    echo -e "\n❌ El servicio NO quedó online (no responde en el puerto $server_port o se reinicia solo)."
    echo "------ systemctl status ------"
    systemctl status "$nombre_dir.service" --no-pager -l | head -n 15
    echo "------ últimas líneas del log (journalctl -u $nombre_dir.service) ------"
    sudo journalctl -u "$nombre_dir.service" -n 40 --no-pager
    echo "------------------------------------------"
    return 1 2>/dev/null || exit 1
fi