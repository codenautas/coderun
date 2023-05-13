#!/bin/bash
#$1: db_name
#$2: target_path
DATABASE=$1
TARGET_PATH="$2/$1"
ROTATE=${3:-"A"}

echo "$DATABASE|$TARGET_PATH|$ROTATE"

LOG_FILE="$TARGET_PATH/backups.log"
DUMP_FILE="$TARGET_PATH/local-dump.psql"
OPTIONS="-F custom --blobs --exclude-table-data his.* --exclude-table-data his_*.* --exclude-table-data mant*.* --exclude-table-data temp*.* --exclude-table-data operaciones*.*"

pg_dump --dbname=$DATABASE --file=$DUMP_FILE $OPCIONES #2>$LOG_FILE

# BACKUP-ROTATION
if [ "$ROTATE"  == "A" ]
then
    ZIP_PREFIX="$TARGET_PATH/$DATABASE-"
    DOW="$(date +%w)"
    if [ "$DOW" == "1" ]
    then
        ZIP_SUFIX="$(date +%Y).gz"
    elif [ "$DOW" == "3" ]
    then
        ZIP_SUFIX="m-$(date +%m).gz"
    elif [ "$DOW" == "5" ]
    then
        WEEK=$(expr $(date +%W) % 6)
        ZIP_SUFIX="w-$WEEK.gz"
    else
        ZIP_SUFIX="d-$DOW.gz"
    fi
    gzip <$DUMP_FILE >$ZIP_PREFIX$ZIP_SUFIX
    echo "$TARGET_PATH/$DATABASE-w-$WEEK.gz"
fi
