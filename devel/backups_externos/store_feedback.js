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
const conOpts  = {
    host: localConfig.db_instrumentacion.host,
    user: localConfig.db_instrumentacion.user,
    port: localConfig.db_instrumentacion.port,
    database: localConfig.db_instrumentacion.database,
    options: `--search_path=${localConfig.db_instrumentacion.schema}`,
    password: localConfig.db_instrumentacion.password
};
var client=undefined;

async function insertBackupLog(record) {
    try {
        await client.query(`INSERT INTO backups_externos (database, servidor, port, fecha, exitoso, error, usuario_db_backup, usuario_pc_responsable)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`, 
            [record.database, record.servidor, record.port, record.fecha, record.exitoso, record.error, record.usuario_db_backup, record.usuario_pc_responsable])
            .execute();
        console.log(`Registro insertado para ${record.database} en ${record.servidor}:${record.port}`);
    } catch (err) {
        console.error(`Error al insertar registro para ${record.database}: ${err.message}`);
    }
}

async function processBackupFeedback() {
    try {
        client = await pg.connect(conOpts)

        const feedbackFile = path.resolve(__dirname, 'local-backup_feedback.txt');
        if (!fs.existsSync(feedbackFile)) {
            throw new Error('El archivo de feedback no existe.');
        }

        const fileContent = fs.readFileSync(feedbackFile, 'utf8');
        const lines = fileContent.split('\n').filter(line => line.trim());

        for (const line of lines) {
            const [database, servidor, hostip, port, fecha, exitoso, error, usuario_db_backup, usuario_pc_responsable] = line.split('|');

            const record = {
                database,
                servidor,
                hostip,
                port: parseInt(port),
                fecha,
                exitoso: exitoso === 'true',
                error: error === 'N/A' ? null : error,
                usuario_db_backup,
                usuario_pc_responsable
            };

            await insertBackupLog(record);
        }

        console.log('Proceso de registro en la base de datos completado.');
    } catch (err) {
        console.error('Error durante el proceso de registro:', err.message);
    } finally {
        client.done();
    }
}

processBackupFeedback();
