#!/bin/bash

# Función para obtener la versión de un paquete instalado
get_version() {
    package=$1
    version=$(dpkg -l | grep $package | awk '{print $2 " :      " $3 " ->           " $5}')
#    version=$(dpkg -l | awk -v package="$package" '$2 == package {print $2 ": " $3}')
    echo "$package: $version"
}

# Función para obtener el puerto en uso de una aplicación
get_port() {
    app=$1
    port=$(netstat -antup | grep $app | awk '{print $4}' | awk -F':' '{print $NF}')
    echo "Puerto en uso para $app: $port"
}

echo "Versiones instaladas:"
echo $(lsb_release -a)

echo ""
echo "Versiones de software instaladas:"
get_version "nginx"
echo ""
get_version "apache2"
echo ""
get_version "postgresql"
echo ""
get_version "mysql"
echo ""
get_version "node"
echo ""
get_version "nvm"
echo ""
get_version "php"

echo ""
echo "Puertos en uso:"
get_port "nginx"
get_port "apache2"
get_port "postgres"
get_port "mysql"
get_port "node"
get_port "php"

