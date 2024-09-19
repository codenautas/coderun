const fs = require('fs');
const { exec } = require('child_process');
const path = require('path');
const archiver = require('archiver');
const yaml = require('js-yaml');

// Leer configuración desde local-config.yaml
function loadConfig() {
    try {
        const configFile = fs.readFileSync('local-config.yaml', 'utf8');
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

    const dumpCommand = `"C:\\Program Files\\PostgreSQL\\16\\bin\\pg_dump.exe" -h ${engine.host} -U ${localConfig.usuario_backup} -F p --blobs --exclude-table-data his.* --exclude-table-data temp.* -f "${dumpFilePath}" ${dbName}`;

    return new Promise((resolve, reject) => {
        const dumpProcess = exec(dumpCommand);

        let stderr = '';
        dumpProcess.stderr.on('data', (data) => {
            stderr += data.toString();
        });

        dumpProcess.on('exit', (code) => {
            if (code === 0) {
                console.log(`Backup de la base de datos ${dbName} completado`);
                resolve(dumpFilePath);
            } else {
                console.error(`Error al realizar el backup de la base de datos ${dbName}`);
                reject(new Error(`pg_dump falló con código ${code}. Detalles: ${stderr}`));
            }
        });

        dumpProcess.on('error', (err) => {
            reject(new Error(`Error al ejecutar pg_dump: ${err.message}`));
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

async function main() {
    console.log('Iniciando proceso de backup desde lista...');
    try {
        const backupListPath = './local-databases_to_backup.txt';
        const backupDirBase = './local-backups/';
        
        if (!fs.existsSync(backupListPath)) {
            throw new Error('El archivo de lista de backups no existe.');
        }

        const fileContent = fs.readFileSync(backupListPath, 'utf8');
        const lines = fileContent.split('\n').filter(line => line.trim());

        for (const line of lines) {
            const [hostPort, dbName] = line.split(',');
            const [host, port] = hostPort.split(':');
            const backupDir = path.join(backupDirBase, `${host}_${port}`);

            if (!fs.existsSync(backupDir)) {
                fs.mkdirSync(backupDir, { recursive: true });
            }

            try {
                const backupPath = await backupDatabase({ host, port }, dbName, backupDir);
                await compressBackup(backupPath);
                fs.unlinkSync(backupPath); // Eliminar el archivo .sql después de comprimir
            } catch (err) {
                console.error(`Error durante el backup de la base de datos ${dbName}: ${err.message}`);
            }
        }

        console.log('Proceso de backup finalizado.');
    } catch (err) {
        console.error('Error durante el proceso de backup:', err.message);
    }
}

main();