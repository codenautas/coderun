const path = require('path');
const { Client } = require('pg');
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
const instrumentacionDBClient = new Client({
    host: localConfig.db_instrumentacion.host,
    user: localConfig.db_instrumentacion.user,
    port: localConfig.db_instrumentacion.port,
    database: localConfig.db_instrumentacion.database,
    options: `--search_path=${localConfig.db_instrumentacion.schema}`,
    password: localConfig.db_instrumentacion.password
});

async function getEnginesToBackup() {
    try {
        const query = `
            SELECT m.puerto AS puerto, s.ip as host, s.servidor, s.usuario_backups_externos, m.producto
            FROM servidores s left join motores m using(servidor)
            where m.producto ='postgres' and s.usuario_backups_externos = $1
            order by s.ip, m.puerto;
        `;
        const res = await instrumentacionDBClient.query(query, [localConfig.usuario_inst_responsable_backup]);
        return res.rows;
    } catch (err) {
        console.error('Error al obtener servidores:', err);
        throw err;
    }
}

async function getDatabases(engine) {
    try {
        const res = await instrumentacionDBClient.query(
            `SELECT database, s.ip, db.port 
            FROM instrumentacion.servidores s 
            left join instrumentacion.databases db using (servidor)
            where s.ip = $1 and db.port = $2 
            AND db.database !~ 'muleto|template|postgres|bkp|bak|capa';
        `,[engine.host, engine.puerto]);
        return res.rows.map(row => row.database);
    } catch (err) {
        console.error('Error al obtener servidores:', err);
        throw err;
    }
}

async function writeDatabasesToFile() {
    try {
        await instrumentacionDBClient.connect();
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
        await instrumentacionDBClient.end();

        console.log(`Lista de bases de datos guardada en ${backupListPath}`);
    } catch (err) {
        console.error('Error durante la generación de la lista de bases de datos:', err);
    }
}

writeDatabasesToFile();
