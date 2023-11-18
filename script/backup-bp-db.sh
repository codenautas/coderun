
#!/bin/bash
#$1: db_name
#$2: target_path
DATABASE=$1
TARGET_PATH="$2/$1"
ROTATE=${3:-"A"}

if [ ${#ROTATE} != 1 ]; then
    PARAM_OPTS=$3
    ROTATE=${4:-"A"}
else
    PARAM_OPTS=""
fi

echo "$DATABASE|$TARGET_PATH|$ROTATE"

LOG_FILE="$TARGET_PATH/backups.log"
DUMP_FILE="$TARGET_PATH/local-dump.psql"
DEF_OPTS=" -F plain --blobs --exclude-table-data his.* --exclude-table-data his_*.* --exclude-table-data mant*.* --exclude-table-data *.bitacora --exclude-table-data temp*.* --exclude-table-table-data operaciones*.* --exclude-schema public"

date +"%y-%m-%d %H:%M" 2>$LOG_FILE
pg_dump --dbname=$DATABASE --file=$DUMP_FILE $PARAM_OPTS $DEF_OPTS #2>$LOG_FILE
date +"%y-%m-%d %H:%M" 2>$LOG_FILE

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
    echo "$TARGET_PATH/$DATABASE-w-$WEEK.gz" 2>$LOG_FILE
fi