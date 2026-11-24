#!/bin/bash
# Generacion nginx para apps que son solo cliente (archivos estaticos en dist).
# Para apps cliente-servidor usar generate-nginx-inst.sh (proxy_pass al puerto).
#
# Usa las variables del yaml de la instancia (/opt/insts/$nombre_dir.yaml, creado por prepare-inst-client.sh):
#   $nombre_dir        nombre de la instancia (carpeta /opt/npm/$nombre_dir)
#   $server_base_url   server.base-url
#   $git_project       git.project (se usa para adivinar el html de entrada)
#   $server_index      server.index html de entrada dentro de dist (lo pide prepare-inst-client.sh)
coderun_version="0.3.1"
echo "Generacion nginx cliente $coderun_version"

if [ -z "$nombre_dir" ]; then
  echo "falta definir \$nombre_dir"
  return 1 2>/dev/null || exit 1
fi
# si no se cargaron las variables del yaml, se cargan
if [ -z "$server_base_url" ]; then
  source /opt/bin/bash-yaml/script/yaml.sh
  create_variables /opt/insts/${nombre_dir}.yaml
fi

dist_dir="/opt/npm/${nombre_dir}/dist"
# html de entrada: server.index del yaml, si no index.html, si no <git.project>.html
if [ -z "$server_index" ]; then
  if [ -f "$dist_dir/index.html" ] || [ -z "$git_project" ]; then
    server_index=index.html
  else
    server_index=${git_project}.html
  fi
fi
if [ ! -f "$dist_dir/$server_index" ]; then
  echo "ATENCION: no existe $dist_dir/$server_index (falta compilar o revisar server.index en el yaml)"
fi

file_name="/opt/nginx.conf/${nombre_dir}.conf"
copia=""
if [ -f $file_name ]; then
  copia=~/copia_${nombre_dir}.conf
  cp $file_name $copia
fi
    cat >$file_name <<NGINX
        location = $server_base_url {
            return 301 $server_base_url/;
        }

        location $server_base_url/ {
            alias $dist_dir/;
            index $server_index;

            add_header Content-Security-Policy "default-src 'self'; connect-src 'none'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'" always;
            add_header X-Content-Type-Options nosniff always;
            add_header X-coderun-version '$coderun_version' always;

            location ~ \.(ts|map)\$|tsconfig\.json\$ {
                return 404;
            }
        }
NGINX
if [ -n "$copia" ]; then
  diff $file_name $copia
fi
