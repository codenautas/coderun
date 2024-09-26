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

// Obtener lista de motores a backupear desde la base de datos 'instrumentacion'
async function getEnginesToBackup() {
    try {
        const query = `
            SELECT m.puerto AS puerto, s.ip as host, s.servidor, s.usuario_backups_externos, m.producto
            FROM servidores s left join motores m using(servidor)
            where m.producto ='postgres' and s.usuario_backups_externos is not null
            order by s.ip, m.puerto;
        `;
        const res = await instrumentacionDBClient.query(query);
        return res.rows;
    } catch (err) {
        console.error('Error al obtener servidores:', err);
        throw err;
    }
}

// Obtener bases de datos desde la base de datos 'instrumentacion'
async function getDatabasesFromInstrumentacion(engine) {
    try {
        const res = await instrumentacionDBClient.query(
            `SELECT database 
            FROM instrumentacion.databases db
            WHERE db.servidor = $1 AND db.port = $2 
            AND db.database !~ 'test|prueba|muleto|template|postgres|bkp|bak|capa';`,
            [engine.servidor, engine.puerto]
        );
        return res.rows.map(row => row.database);
    } catch (err) {
        console.error('Error al obtener bases de datos de instrumentacion:', err);
        throw err;
    }
}

// Obtener bases de datos reales del motor PostgreSQL
async function getDatabasesFromEngine(engine) {
    const engineClient = new Client({
        host: engine.host,
        user: localConfig.usuario_backup,
        port: engine.puerto,
        password: localConfig.password_backup,
        database: 'postgres' // Conectamos a la base de datos 'postgres' para listar las demás
    });

    try {
        await engineClient.connect();
        const query = `
            SELECT datname FROM pg_database 
            WHERE datname NOT LIKE '%test%' 
            AND datname NOT LIKE '%prueba%' 
            AND datname NOT LIKE '%muleto%' 
            AND datname NOT LIKE '%template%' 
            AND datname NOT LIKE '%postgres%' 
            AND datname NOT LIKE '%bkp%' 
            AND datname NOT LIKE '%bak%' 
            AND datname NOT LIKE '%capa%' 
            ORDER BY 1;
        `;
        const res = await engineClient.query(query);
        return res.rows.map(row => row.datname);
    } catch (err) {
        console.error(`Error al obtener bases de datos del motor PostgreSQL en ${engine.host}:${engine.puerto}`, err);
        return [];
    } finally {
        await engineClient.end();
    }
}

// Limpiar los archivos antes de comenzar
function cleanFiles() {
    const notInEngineFile = './match/local-databases_not_in_engine.txt';
    const notInInstrumentacionFile = './match/local-databases_not_in_instrumentacion.txt';

    // Limpiar ambos archivos sobreescribiéndolos con contenido vacío
    fs.writeFileSync(notInEngineFile, '', 'utf8');
    fs.writeFileSync(notInInstrumentacionFile, '', 'utf8');

    console.log('Archivos limpiados.');
}

// Escribir diferencias en archivos globales
function writeDifferences(instrumentacionDbs, engineDbs, engine) {
    const notInEngine = instrumentacionDbs.filter(db => !engineDbs.includes(db));
    const notInInstrumentacion = engineDbs.filter(db => !instrumentacionDbs.includes(db));

    const notInEngineFile = './match/local-databases_not_in_engine.txt';
    const notInInstrumentacionFile = './match/local-databases_not_in_instrumentacion.txt';

    if (notInEngine.length) {
        const notInEngineContent = `\n${engine.servidor} ${engine.host}:${engine.puerto}\n` + notInEngine.join('\n') + '\n';
        fs.appendFileSync(notInEngineFile, notInEngineContent, 'utf8');
    }

    if (notInInstrumentacion.length) {
        const notInInstrumentacionContent = `\n${engine.servidor} ${engine.host}:${engine.puerto}\n` + notInInstrumentacion.join('\n') + '\n';
        fs.appendFileSync(notInInstrumentacionFile, notInInstrumentacionContent, 'utf8');
    }

    console.log(`Diferencias escritas en ${notInEngineFile} y ${notInInstrumentacionFile}`);
}

// Función principal para comparar bases de datos
async function compareDatabases() {
    try {
        await instrumentacionDBClient.connect();
        const engines = await getEnginesToBackup();
        cleanFiles();

        for (const engine of engines) {
            // Obtener bases de datos de ambas fuentes
            const instrumentacionDbs = await getDatabasesFromInstrumentacion(engine);
            const engineDbs = await getDatabasesFromEngine(engine);

            // Comparar y escribir diferencias
            if (instrumentacionDbs.length || engineDbs.length){
                writeDifferences(instrumentacionDbs, engineDbs, engine);
            }
        }

        await instrumentacionDBClient.end();
        console.log('Comparación de bases de datos completada.');
    } catch (err) {
        console.error('Error durante la comparación de bases de datos:', err);
    }
}

compareDatabases();
