#!/bin/bash
coderun_version="0.2.2"
echo "Preparando instalación $coderun_version"
echo "Definir primero el nombre de instancia."
echo 'Se exportara como $nombre_dir'
echo 'Se usara para crear la carpeta /opt/$nombre_dir con la aplicacion y los archivos de configuracion'
echo '/opt/inst/$nombre_dir.yaml'
echo '/opt/nginx.conf/$nombre_dir.conf'
echo '/opt/services/$nombre_dir.service'
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
  read -p "https://$git_host.com/[codenautas]:" git_group
  git_group=${git_group:-codenautas}
  read -p "https://$git_host.com/$git_group/[$inst_name]:" git_project
  git_project=${git_project:-$inst_name}

  echo "# db section"
  read -p "host [DIRECT]:" db_host
  db_host=${db_host:-DIRECT}
  echo "por ahora tengo $db_host"
  if [[ $db_host == "DIRECT" ]]; then
    echo "veo DIRECTO"
    db_host_port_section=""
  else
    read -p "port [5432]:" db_port
    db_port=${db_port:-5432}
    db_host_port_section=""
    db_host_port_section+=$'\n'
    db_host_port_section+="  host: $db_host" 
    db_host_port_section+=$'\n'
    db_host_port_section+="  port: $db_port"
YAML
    echo "PREGUNTÉ POR LA SECCION $db_host_port_section"
  fi
  read -p "database [${inst_name}_db]:" db_name
  db_name=${db_name:-${inst_name}_db}
  read -p "username [${inst_name}_admin]:" db_user
  db_user=${db_user:-${inst_name}_admin}
  read -p "owner [${inst_name}_owner]:" db_owner
  db_owner=${db_owner:-${inst_name}_owner}
  db_pass=''
  while [[ -z "$db_pass" ]]
    do
      read -p "password:" db_pass
    done


  echo "por instalar $inst_name en $port sobre /$base_url desde https://$git_host.com/$git_group/$git_project"
  echo "db: $db_name usuario para conexion: $db_user owner: $db_owner"

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
git:
  project: $git_project
  group: $git_group
  host: https://$git_host.com
db:$db_host_port_section
  database: $db_name
  user: $db_user
  password: $db_pass
install:
  dump:
    db:
      owner: $db_owner
YAML
    echo "se exporto la variable \$nombre_dir=$nombre_dir"
  fi
fi
