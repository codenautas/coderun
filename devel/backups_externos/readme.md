Pasos para configurar tarea programada para backups externos

- $ cd c:/dev/github
- $ git clone https://github.com/codenautas/coderun
- $ cd coderun/devel/backups_externos/
- $ npm i
- copio example-local-config.yaml a local-config.yaml y lo lleno con la info de la db remota de instrumentacion
- pruebo correr las tareas desde la terminal
    * node get_databases.js  (veo que genere archivo local-databases_to_backup.txt y que el contenido sea correcto)
    * node backup_databases.js (me fijo que genere la carpeta local-backups y me fijo que los backups se guarden ahí, luego chequeo que cada backup que se esté haciendo se esté registrando en archivo local-backup_feedback.txt, luego paro el script (va a tardar mucho hay que correrlo de madrugada))
    * node store_feedback.js (chequeo que en instrumentación se hayan agregado las rows del archivo de feedback)
- programo tareas de windows
    * 22hs -> "traer_lista_DBs_para_backup_externo" (node get_databases.js)
    * 1 o 2 am -> "realizar_backup_externo" (node backup_datbases.js)
    * 7am -> "guardar_feedback_de_último_backup_en_db_instrumentacion" (node store_feedback.js)

conf de la tarea programada:
- programa o script: "C:\Program Files\nodejs\node.exe" (asi con comillas)
- agregar argumentos (opc): get_databases.js (o el script que corresponda)
- iniciar en (opc): C:\dev\github\coderun\devel\backups_externos (o path absoluto que corresponda)
