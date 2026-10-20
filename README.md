# coderun
code runner for server instrumentation



## script/comparar-bd.js

Compara una base existente (por ejemplo el backup de producción restaurado) contra una base de referencia (el esquema que espera el código, armado a cero) y escribe el script SQL con las diferencias, repetible. Para instalaciones muy atrasadas o de las que no se sabe qué scripts de `operaciones/` se aplicaron. Solo ve la estructura; lo que depende de los datos queda marcado "completar" en el script.

```sh
PGPASSWORD=... node script/comparar-bd.js --referencia app_ref_db --origen app_backup_db --admin app_admin \
    --datos modos_dm,roles --salida diferencias.sql
```

Opciones y detalles en el encabezado del archivo. Necesita `psql` y `pg_dump`; no usa módulos de npm.
