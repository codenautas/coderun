#!/bin/bash
#$1: source_path
#$2: db_name
DATABASE=$2
SOURCE_PATH=$1
ori_install_dump_db_owner=$3
ori_db_user=$4
install_dump_db_owner=$5
db_user=$6
TODAY=$(date '+%Y-%m-%d')

LOG_FILE="$SOURCE_PATH/repopulate.log"

FILTER_FILE="$SOURCE_PATH/filter.filter"
if [ -f $FILTER_FILE ]; then
  FILTER=$(cat $FILTER_FILE)
  echo "filter: $FILTER" &>> $LOG_FILE
else
  FILTER=""
  echo "no filter" &>> $LOG_FILE
fi

echo "repopulate $SOURCE_PATH|$DATABASE|ori_install_dump_db_owner=$ori_install_dump_db_owner|" + \
  "ori_db_user=$ori_db_user|install_dump_db_owner=$install_dump_db_owner|db_user=$db_user $(date +"%y-%m-%d %H:%M")" &>> $LOG_FILE

DUMP_FILE="$SOURCE_PATH/local-dump.psql"
MULETO_FILE="$SOURCE_PATH/muleto-dump.psql"

muleto_auto_clone_db_since=$(psql --no-align --tuples-only \
  --command="select to_char(muleto_auto_clone_db_since,'YYYY-MM-DD') from public.backend_plus;" $DATABASE)

if [[ $muleto_auto_clone_db_since < $TODAY ]]
then
  sed -e "s/${ori_install_dump_db_owner}/${install_dump_db_owner}/g ; s/${ori_db_user}/${db_user}/g $FILTER" $DUMP_FILE | \
    sed "1i do \$\$ begin execute (select drop_schemas_sql from public.backend_plus); end; \$\$;" > $MULETO_FILE
  echo "$(ls -s $MULETO_FILE) $(date +"%y-%m-%d %H:%M")" &>> $LOG_FILE
  psql -v ON_ERROR_STOP=on --quiet --single-transaction --pset pager=off --file $MULETO_FILE $DATABASE 2>> $LOG_FILE
  rm $MULETO_FILE
else
  echo "not repopulating muleto until $muleto_auto_clone_db_since." &>> $LOG_FILE
fi
date +"%y-%m-%d %H:%M" &>> $LOG_FILE
