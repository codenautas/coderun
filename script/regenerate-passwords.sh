#!/bin/bash

source /opt/bin/bash-yaml/script/yaml.sh

instalaciones="/opt/insts/*.yaml"

echo "-- ATENCION! No guardar este archivo nunca. Usar pipes para ejecutarlo"
echo "-- . /opt/bin/coderun/script/regenerate-passwords.sh | sudo -u postgres psql"

for instalacion in $(ls $instalaciones); do
  create_variables $instalacion
  echo "alter user $db_user with password '${db_password//\'/\'\'}';"
done
