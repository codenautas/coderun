#!/bin/bash
coderun_version="0.2.0"
echo "Generacion de todos los archivos de configuracion $coderun_version"
if [ -d /opt/nginx.conf ]; then
  ./generate-nginx-insts.sh
fi
if [ -d /opt/caddy.conf ]; then
  ./generate-caddy-insts.sh
fi
if [ -d /opt/services ]; then
  ./generate-service-insts.sh
fi
