#!/bin/bash
#$1: source_path
#$2: db_name
DATABASE=$2
SOURCE_PATH=$1
ori_install_dump_db_owner=$3
ori_db_user=$4
install_dump_db_owner=$5
db_user=$6

LOG_FILE="$SOURCE_PATH/repopulate.log"

echo "repopulate $SOURCE_PATH|$DATABASE|ori_install_dump_db_owner=$ori_install_dump_db_owner|ori_db_user=$ori_db_user|install_dump_db_owner=$install_dump_db_owner|db_user=$db_user $(date +"%y-%m-%d %H:%M")" &>> $LOG_FILE

DUMP_FILE="$SOURCE_PATH/local-dump.psql"
MULETO_FILE="$SOURCE_PATH/muleto-dump.psql"

MULETO_AUTO_DB=$(psql --no-align --tuples-only --command="select value from public.backend_plus where param = 'muleto_auto_db';" $DATABASE)

if [ "$MULETO_AUTO_DB" == "true" ]
then
  sed -e "s/${ori_install_dump_db_owner}/${install_dump_db_owner}/g ; s/${ori_db_user}/${db_user}/g " $DUMP_FILE | \
    sed "1i do \$\$ begin execute (select value #>> '{}' from public.backend_plus where param='drop_schemas_sql'); end; \$\$;" > $MULETO_FILE
  echo "$(ls -s $MULETO_FILE) $(date +"%y-%m-%d %H:%M")" &>> $LOG_FILE
  psql -v ON_ERROR_STOP=on --quiet --single-transaction --pset pager=off --file $MULETO_FILE $DATABASE 2>> $LOG_FILE
  rm $MULETO_FILE
else
  echo "not repopulating muleto_auto_db=$MULETO_AUTO_DB." &>> $LOG_FILE
fi
date +"%y-%m-%d %H:%M" &>> $LOG_FILE
