export PGHOST="$PWD/local-pg"
export PGDATA="$PGHOST/data"
export PGUSER=postgres
PGPORT=$(yq '.db.port // ""' local-config.yaml 2>/dev/null)
export PGPORT

start_pg_if_stopped() {
  if pg_ctl status > /dev/null; then
    return 0
  fi
  pg_ctl start --wait --log="$PGHOST/postgres.log" --options="-k $PGHOST -h localhost -p $PGPORT" > /dev/null
}
