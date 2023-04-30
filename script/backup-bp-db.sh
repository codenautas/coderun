#!/bin/bash
#$1: db_name
#$2: target_path
DATABASE=$1
TARGET_PATH=${2:-"."}
ROTATE=${3:-"A"}

echo "$DATABASE|$TARGET_PATH|$ROTATE"

LOG_FILE="$TARGET_PATH/backups.log"
DUMP_FILE="$TARGET_PATH/last-backup.backup"
OPTIONS="-F custom --blobs --exclude-table-data his.* --exclude-table-data his_*.* --exclude-table-data mant*.* --exclude-table-data temp*.* --exclude-table-data operaciones*.*"

pg_dump --dbname=$DATABASE --file=$DUMP_FILE $OPCIONES #2>$LOG_FILE

# BACKUP-ROTATION
if [ "$ROTATE"  == "A" ]
then
    DAILY="$TARGET_PATH/$DATABASE-d-$(date +%w).gz"
    gzip <$DUMP_FILE >$DAILY
    cp $DAILY "$TARGET_PATH/$DATABASE-$(date +%Y).gz"
    cp $DAILY "$TARGET_PATH/$DATABASE-m-$(date +%m).gz"
    WEEK=$(expr $(date +%W) % 6)
    cp $DAILY "$TARGET_PATH/$DATABASE-w-$WEEK.gz"
    echo "$TARGET_PATH/$DATABASE-w-$WEEK.gz"
fi
