# Backups externos

## Descripción

Este proyecto permite generar backups de bases de datos externas y registrar el feedback en la base de instrumentación.

## Opciones de ejecución

### 1️⃣ Paso a paso (manual)

1. **Clonar el repositorio y entrar al directorio**:

   ```bash
   cd c:/dev/github
   git clone https://github.com/codenautas/coderun
   cd coderun/devel/backups_externos/
   ```

2. **Instalar dependencias**:

   ```bash
   npm i
   ```

3. **Configurar** el archivo `local-config.yaml` copiando `example-local-config.yaml` y completando la información de la base de datos remota.

4. **Ejecutar cada script individualmente**:

   ```bash
   node get_databases.js      # genera local-databases_to_backup.txt
   node backup_databases.js   # crea la carpeta local-backups y escribe local-backup_feedback.txt
   node store_feedback.js     # inserta el feedback en la base de datos de instrumentación
   ```

#### Configurar tareas programadas de Windows (ejecución paso a paso)

Para automatizar cada script por separado, crear tres tareas en el Programador de tareas:

* **Tarea 1 – Obtener lista de bases**
  * Programa o script: `"C:\Program Files\nodejs\node.exe"`
  * Argumentos: `get_databases.js`
  * Iniciar en: `C:\dev\github\coderun\devel\backups_externos`
  * Programar a la hora deseada (ej. 22:00).
* **Tarea 2 – Realizar backup**
  * Programa o script: `"C:\Program Files\nodejs\node.exe"`
  * Argumentos: `backup_databases.js`
  * Iniciar en: mismo directorio.
  * Programar a la hora deseada (ej. 01:00).
* **Tarea 3 – Guardar feedback**
  * Programa o script: `"C:\Program Files\nodejs\node.exe"`
  * Argumentos: `store_feedback.js`
  * Iniciar en: mismo directorio.
  * Programar a la hora deseada (ej. 07:00).

En cada tarea marcar la opción **"Ejecutar tanto si el usuario inició sesión como si no"**.

### 2️⃣ Todo en uno (simplificado)

Ejecuta los tres scripts en un solo paso con:

```bash
npm run all   # o
node run-all.js
```

Este comando ejecuta secuencialmente `get_databases.js`, `backup_databases.js` y `store_feedback.js`.

#### Configurar tarea programada de Windows (todo en uno)

Crear una única tarea que invoque el script `run-all.js`:

* **Programa o script:** `"C:\Program Files\nodejs\node.exe"`
* **Argumentos:** `run-all.js`
* **Iniciar en:** `C:\dev\github\coderun\devel\backups_externos`
* **Programación:** la hora que prefieras (ej. 02:00).
* Marcar **"Ejecutar tanto si el usuario inició sesión como si no"**.

## Verificación manual

Acceder a:

https://pro.estadisticaciudad.gob.ar/inst/menu#i=backups,backups_externos

para comprobar que los backups se estén realizando correctamente.
