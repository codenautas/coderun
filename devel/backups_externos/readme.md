
$ cd c:/dev/github
$ git clone https://github.com/codenautas/coderun
$ npm i
- copio example-local-config.yaml a local-config.yaml y lo lleno con la info de la db remota de instrumentacion
- programo tareas de windows
    * 22hs -> "traer_lista_DBs_para_backup_externo" (node get_databases.js)
    * 1 o 2 am -> "realizar_backup_externo" (node backup_datbases.js)
    * 7am -> "guardar_feedback_de_último_backup_en_db_instrumentacion" (node store_feedback.js)

conf de la tarea programada:
- programa o script: "C:\Program Files\nodejs\node.exe" (asi con comillas)
- agregar argumentos (opc): get_databases.js (o el script que corresponda)
- iniciar en (opc): C:\dev\github\coderun\devel\backups_externos (o path absoluto que corresponda)
