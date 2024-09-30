const fs = require('fs');
const { exec } = require('child_process');
const path = require('path');
const archiver = require('archiver');
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

async function backupDatabase(engine, dbName, backupDir) {
    console.log(`Iniciando backup de la base de datos: ${dbName} en el engine: ${engine.host}:${engine.port}`);

    const dumpFilePath = path.join(backupDir, `${dbName}.sql`);
    const dumpCommand = `"C:\\Program Files\\PostgreSQL\\16\\bin\\pg_dump.exe" -h ${engine.host} -p ${engine.port} -U ${localConfig.usuario_backup} -F p --blobs --exclude-table-data temp.* --exclude-table-data his.* --exclude-table-data his_. --exclude-table-data mant*.* --exclude-table-data .bitacora --exclude-table-data *.summary --exclude-table-data *.tokens --exclude-table-data temp.* --exclude-table-data operaciones*.* --exclude-schema public -f "${dumpFilePath}" ${dbName}`;

    return new Promise((resolve, reject) => {
        const dumpProcess = exec(dumpCommand);
        let stderr = '';
        dumpProcess.stderr.on('data', (data) => {
            stderr += data.toString();
        });

        dumpProcess.on('exit', (code) => {
            if (code === 0) {
                console.log(`Backup de la base de datos ${dbName} completado`);
                resolve({ success: true, dumpFilePath });
            } else {
                console.error(`Error al realizar el backup de la base de datos ${dbName}`);
                reject({ success: false, error: `Error al terminar pg_dump: <<${dumpCommand}>>, falló con código <<${code}>>, Detalles: <<${stderr.replace(/[\r\n]+/g, '')}>>` });
            }
        });

        dumpProcess.on('error', (err) => {
            reject({ success: false, error: `Error ejecución pg_dump: <<${dumpCommand}>>, falló con error: <<${err.message}>>` });
        });
    });
}

async function compressBackup(filePath) {
    const zipFilePath = `${filePath}.zip`;
    const output = fs.createWriteStream(zipFilePath);
    const archive = archiver('zip', { zlib: { level: 9 } });
    output.on('close', () => {
        console.log(`Backup comprimido en: ${zipFilePath}`);
    });

    archive.on('error', (err) => {
        throw err;
    });

    archive.pipe(output);
    archive.file(filePath, { name: path.basename(filePath) });
    await archive.finalize();

    return zipFilePath;
}

async function logBackupResult(fileToSave, engine, success, error) {
    const feedbackFile = path.resolve(__dirname, fileToSave);
    const logEntry = `${engine.dbName}|${engine.servidor}|${engine.host}|${engine.port}|${new Date().toISOString()}|${success}|${error || 'N/A'}|${localConfig.usuario_backup}|${engine.usuarioInstResponsable}\n`;

    fs.appendFileSync(feedbackFile, logEntry);
}

// Función para vaciar el archivo o crearlo si no existe
async function clearOrCreateFeedbackFile(feedbackFile) {
    // Abre el archivo en modo escritura, si no existe lo crea
    fs.openSync(feedbackFile, 'w');

    // Vaciar el archivo sobreescribiéndolo con contenido vacío
    fs.writeFileSync(feedbackFile, '', 'utf8');
    console.log('Archivo de feedback vaciado o creado.');
}

async function main() {
    console.log('Iniciando proceso de backup desde lista...');
    try {
        const backupListPath = path.resolve(__dirname, './local-databases_to_backup.txt');
        const backupDirBase = path.resolve(__dirname, './local-backups/');
        
        if (!fs.existsSync(backupListPath)) {
            throw new Error('El archivo de lista de backups no existe.');
        }

        const fileContent = fs.readFileSync(backupListPath, 'utf8');
        const lines = fileContent.split('\n').filter(line => line.trim());
        
        const feedbackFile = path.resolve(__dirname, 'local-backup_feedback.txt');
        await clearOrCreateFeedbackFile(feedbackFile);

        for (const line of lines) {
            const [servidor, hostPort, dbName, usuarioInstResponsable] = line.split(',');
            const [host, port] = hostPort.split(':');
            const backupDir = path.join(backupDirBase, `${servidor}${host}/${port}`);
            const datosLog = {dbName, servidor, host, port, usuarioInstResponsable };

            if (!fs.existsSync(backupDir)) {
                fs.mkdirSync(backupDir, { recursive: true });
            }

            try {
                const { success, dumpFilePath, error } = await backupDatabase({ host, port }, dbName, backupDir);
                if (success) {
                    await compressBackup(dumpFilePath);
                    fs.unlinkSync(dumpFilePath); // Eliminar el archivo .sql después de comprimir
                }
                await logBackupResult('local-backup_feedback.txt', datosLog, success, error);
            } catch (err) {
                console.error(`Error durante el backup de la base de datos ${dbName}: ${err.error}`);
                await logBackupResult('local-backup_feedback.txt', datosLog, false, err.error);
                await logBackupResult('local-errors.txt', datosLog, false, err.error);
            }
        }

        console.log('Proceso de backup finalizado.');
    } catch (err) {
        console.error('Error durante el proceso de backup:', err.message);
    }
}

main();
