#!/bin/bash
# Version de prepare-inst.sh para apps que son solo cliente (archivos estaticos en dist).
# Crea /opt/insts/$nombre_dir.yaml solo con las secciones coderun, server y git
# (sin base de datos). Despues se usa con generate-nginx-inst-client.sh
coderun_version="0.3.1"
echo "Preparando instalación cliente $coderun_version"
echo "Definir primero el nombre de instancia."
echo 'Se exportara como $nombre_dir'
echo 'Se usara para crear la carpeta /opt/npm/$nombre_dir con la aplicacion y los archivos de configuracion'
echo '/opt/insts/$nombre_dir.yaml'
echo '/opt/nginx.conf/$nombre_dir.conf'
read -p 'Nombre de instancia (o sea dir):' inst_name
file_name="/opt/insts/$inst_name.yaml"
if [[ -z "$inst_name" ]]; then
  echo "debe poner el nombre de instancia"
elif [[ -f "$file_name" ]]; then
  echo "ya existe el archivo $file_name"
  echo "no se puede crear la instancia"
else
  nombre_dir=$inst_name
  echo "# server section"
  port=''
  while [[ -z "$port" ]]
    do
      read -p 'Server port:' port
    done
  read -p "Base URL /[$inst_name]:" base_url
  base_url=${base_url:-$inst_name}
  read -p "SO user [$inst_name]:" so_user
  so_user=${so_user:-$inst_name}

  echo "# git section"
  read -p "https://[github].com:" git_host
  git_host=${git_host:-github}
  read -p "https://$git_host.com/[es-ba]:" git_group
  git_group=${git_group:-es-ba}
  read -p "https://$git_host.com/$git_group/[$inst_name]:" git_project
  git_project=${git_project:-$inst_name}

  echo "# server index (html de entrada dentro de dist)"
  read -p "index [$git_project.html]:" index
  index=${index:-$git_project.html}

  echo "por instalar $inst_name (solo cliente) en $port sobre /$base_url (index $index) desde https://$git_host.com/$git_group/$git_project"

  ok=''
  while [[ -z "$ok" ]]
    do
      read -p "ok:" ok
    done
  if [[ $ok =~ ^[Nn] ]]; then
     echo "abortado"
  else
    echo "preparando"
    cat >$file_name <<YAML
coderun:
  version: $coderun_version
server:
  port: $port
  base-url: /$base_url
  user: $so_user
  index: $index
git:
  project: $git_project
  group: $git_group
  host: https://$git_host.com
YAML
    echo "se exporto la variable \$nombre_dir=$nombre_dir"
    echo "se creó $file_name"
    read -p "¿Crear la instancia ahora con generate-inst-client.sh? (s/n): " crear
    if [[ "$crear" =~ ^[Ss]$ ]]; then
      bash "$(dirname "${BASH_SOURCE[0]}")/generate-inst-client.sh" "$nombre_dir"
    else
      echo "para crearla después: generate-inst-client.sh $nombre_dir"
    fi
  fi
fi
