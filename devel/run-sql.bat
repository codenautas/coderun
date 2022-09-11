@echo off
setlocal enabledelayedexpansion
set single_transaction=-v ON_ERROR_STOP=on --single-transaction --pset pager=off --quiet
if "%1" == "path" (
  echo agregando el path
  set "Path=%path%;%~2;"
) else if "%1" == "create-db" (
  psql --file=local-db-dump-create-db.sql
) else if "%1" == "" (
  psql --no-password -c "select version() as ""postgres version"""
  echo %0 create-db
  echo %0 create-schema
  echo %0 other.sql database_db
) else (
  if "%1" == "create-schema" (
    set script=local-db-dump.sql
  ) else (
    set script=%1
  )
  if "%2" == "" (
    set vi_db=no_todavia
    FOR /F "tokens=1* delims=:" %%i IN (local-config.yaml) DO (
      if "%%i" == "db" (
        set vi_db=solo_el_grupo
      )
      if "%%i" == "  database" (
        if !vi_db! == solo_el_grupo (
          call %0 %* %%j
          set vi_db=si_y_ya_esta
        )
      )
    )
    if not !vi_db! == si_y_ya_esta (
      echo falta el nombre de la base de datos y no se pudo leer de local-config.yaml
      echo se la puede especificar como parametro, por ejemplo
      echo %0 %1 esta_db
    )
  ) else (
    psql --file=!script! %single_transaction% %2
  )
)
if errorlevel 9009 (
  echo No se encontro el psql. Probar agregarlo al path con:
  echo %0 path "C:\Program Files\PostgreSQL\12\bin"
) else if errorlevel 1 (
  if "%PGPORT%" == "" (
    echo Quizas haya que agregar el puerto, el usuario o la clave
    echo set PGPORT=54313
    echo set PGUSER=postgres
    echo set PGPASSWORD=admin
  )
  echo err-code: %errorlevel%
)
