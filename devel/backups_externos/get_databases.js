const path = require('path');
const pg = require('pg-promise-strict');
const fs = require('fs');
const yaml = require('js-yaml');

// Leer configuración desde local-config.yaml
function loadConfig() {
    try {
        const configFile = fs.readFileSync(path.resolve(__dirname, 'local-config.yaml'), 'utf8');
        return yaml.load(configFile);
    } catch (e) {
        console.error('Error al cargar la configuración:', e);
        process.exit(1);
    }
}
// Obtener configuración
const localConfig = loadConfig();
const conOpts = {
    host: localConfig.db_instrumentacion.host,
    user: localConfig.db_instrumentacion.user,
    port: localConfig.db_instrumentacion.port,
    database: localConfig.db_instrumentacion.database,
    options: `--search_path=${localConfig.db_instrumentacion.schema}`,
    password: localConfig.db_instrumentacion.password
};
var client=undefined;

async function getEnginesToBackup() {
    try {
        const query = `select * from vw_get_engines WHERE usuario_backups_externos = $1`;
        const res = await client.query(query, [localConfig.usuario_inst_responsable_backup]).fetchAll();
        return res.rows;
    } catch (err) {
        console.error('Error al obtener servidores:', err);
        throw err;
    }
}

async function getDatabases(engine) {
    try {
        const getDBQuery = `SELECT * from vw_get_databases WHERE ip = $1 and port = $2 
                            AND database !~ 'muleto|template|postgres|bkp|bak|capa|old|hasta'`
        const res = await client.query(getDBQuery,[engine.host, engine.puerto]).fetchAll();
        // ###################################
        // TODO VOLVER A AGREGAR AL PATRON test|prueba|
        // ###################################
        return res.rows.map(row => row.database);
    } catch (err) {
        console.error('Error al obtener servidores:', err);
        throw err;
    }
}

async function writeDatabasesToFile() {
    try {
        client = await pg.connect(conOpts)
        const engines = await getEnginesToBackup();
        const backupListPath = './local-databases_to_backup.txt';
        const writeStream = fs.createWriteStream(backupListPath);

        for (const engine of engines) {
            const databases = await getDatabases(engine);
            for (const dbName of databases) {
                writeStream.write(`${engine.servidor},${engine.host}:${engine.puerto},${dbName},${localConfig.usuario_inst_responsable_backup}\n`);
            }
        }
        writeStream.end();
        
        console.log(`Lista de bases de datos guardada en ${backupListPath}`);
    } catch (err) {
        console.error('Error durante la generación de la lista de bases de datos:', err);
    } finally {
        client.done();
    }
}

writeDatabasesToFile();
