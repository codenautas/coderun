
$ cd c:/dev/github
$ git clone https://github.com/codenautas/coderun
$ npm i
- copio example-local-config.yaml a local-config.yaml y lo lleno con la info de la db remota de instrumentacion
- programo tareas de windows
    * 22hs -> node get_databases.js
    * 1 o 2 am -> node backup_datbases.js
    * 7am -> node store_feedback.js
