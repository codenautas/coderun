#!/bin/bash
echo Preparando instalación v0.1.0
read -p 'Nombre de instancia:' inst_name
if [[ -z "$inst_name" ]]; then
  echo "debe poner el nombre de instancia"
else

  echo "# server section"
  port=''
  while [[ -z "$port" ]]
    do
      read -p 'Server port:' port
    done
  read -p "Base URL /[$inst_name]:" base_url
  base_url=${base_url:-$inst_name}

  echo "# git section"
  read -p "https://[github].com:" git_host
  git_host=${git_host:-github}
  read -p "https://$git_host.com/[codenautas]:" git_group
  git_group=${git_group:-codenautas}
  read -p "https://$git_host.com/$git_group/[$inst_name]:" git_project
  git_project=${git_project:-$inst_name}

  echo "# db section"
  read -p "database [${inst_name}_db]:" db_name
  db_name=${db_name:-${inst_name}_db}
  read -p "username [${inst_name}_admin]:" db_user
  db_user=${db_user:-${inst_name}_admin}
  db_pass=''
  while [[ -z "$db_pass" ]]
    do
      read -p "password:" db_pass
    done
  read -p "owner [${inst_name}_owner]:" db_owner
  db_owner=${db_user:-${inst_name}_owner}
  echo "el owner va sin password"

  echo "por instalar $inst_name en $port sobre /$base_url desde https://$git_host.com/$git_group/$inst_name"
  echo "db: $db_name user for connect: $db_user owner: $db_owner"

  ok=''
  while [[ -z "$ok" ]]
    do
      read -p "ok:" ok
    done
  if [[ $ok =~ ^[Nn] ]]; then
     echo "abortado"
  else
    echo "preparando"
  fi
fi