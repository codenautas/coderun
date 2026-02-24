#!/usr/bin/env node
const fs = require("fs");
const os = require("os");
const path = require("path");
const inquirer = require("inquirer").default;
const { spawn } = require("child_process");
const archiver = require("archiver");
const yaml = require("js-yaml");

//
// ─── LEER CONFIG ─────────────────────────────────────────────
//
function loadConfig() {
  try {
    const configFile = fs.readFileSync(path.resolve("./local-config.yaml"), "utf8");
    return yaml.load(configFile);
  } catch (e) {
    console.error("❌ Error al cargar la configuración:", e);
    process.exit(1);
  }
}

const localConfig = loadConfig();

//
// ─── VERIFICAR .PGPASS ──────────────────────────────────────
//
function tieneEntradaPgpass({ host, port, user, database }) {
  const pgpassPath = path.join(os.homedir(), "AppData", "Roaming", "postgresql", "pgpass.conf");
  if (!fs.existsSync(pgpassPath)) return false;

  const lines = fs.readFileSync(pgpassPath, "utf8").split("\n");
  return lines.some(line => {
    const [h, p, db, u, pwd] = line.trim().split(":");
    if (!h || h.startsWith("#")) return false;
    return (
      (h === host || h === "*" || (host === "localhost" && (h === "127.0.0.1" || h === "::1"))) &&
      (p === String(port) || p === "*") &&
      (db === database || db === "*") &&
      (u === user || u === "*") &&
      pwd
    );
  });
}

//
// ─── BACKUP DB ───────────────────────────────────────────────
//
async function backupDatabase({ host, port, user, dbName, rutaPgDump, backupDir, filename }) {
  console.log(`\n🚀 Iniciando backup de ${dbName} (${host}:${port})...`);

  const dumpFilePath = path.join(backupDir, `${filename}.sql`);
  const dumpArgs = [
    "-h", host,
    "-p", port,
    "-U", user,
    "-F", "p",
    "-f", dumpFilePath,
    dbName
  ];

  if (!tieneEntradaPgpass({ host, port, user, database: dbName })) {
    throw new Error(`No se encontró entrada válida en .pgpass para ${host}:${port}:${dbName}:${user}`);
  }

  return new Promise((resolve, reject) => {
    const dumpProcess = spawn(rutaPgDump, dumpArgs, { stdio: ["ignore", "inherit", "pipe"] });
    let stderr = "";

    dumpProcess.stderr.on("data", data => {
      stderr += data.toString();
    });

    dumpProcess.on("exit", code => {
      if (code === 0) {
        console.log(`✅ Backup completo: ${dumpFilePath}`);
        resolve(dumpFilePath);
      } else {
        reject(new Error(`pg_dump falló (código ${code}): ${stderr.replace(/[\r\n]+/g, " ")}`));
      }
    });

    dumpProcess.on("error", err => {
      reject(new Error(`Error ejecutando pg_dump: ${err.message}`));
    });
  });
}

//
// ─── COMPRIMIR ───────────────────────────────────────────────
//
async function compressBackup(filePath) {
  const zipFilePath = `${filePath}.zip`;
  const output = fs.createWriteStream(zipFilePath);
  const archive = archiver("zip", { zlib: { level: 9 } });

  return new Promise((resolve, reject) => {
    output.on("close", () => {
      console.log(`📦 Backup comprimido: ${zipFilePath}`);
      resolve(zipFilePath);
    });

    archive.on("error", err => reject(err));

    archive.pipe(output);
    archive.file(filePath, { name: path.basename(filePath) });
    archive.finalize();
  });
}

// Definimos los entornos disponibles
const environments = [
  { name: "si-prod-db", host: "10.35.100.22", port: 5432 },
  { name: "si-prod-test", host: "10.35.120.22", port: 5432 },
];

// Construimos dinámicamente las opciones para inquirer
const envChoices = environments.map(env => ({
  name: `${env.name} (${env.host}:${env.port})`,
  value: env,
}));

async function main() {
    const { envChoice, prefix } = await inquirer.prompt([
    {
      type: "list",
      name: "envChoice",
      message: "¿De dónde querés sacar el backup?",
      choices: envChoices,
    },
    {
      type: "list",
      name: "prefix",
      message: "Elegí el prefijo del sistema:",
      choices: ["sicuidados", "sidnnya", "sidemo", "sigba"],
    },
  ]);

  const FECHA = new Date().toISOString().slice(0, 10).replace(/-/g, "");
  const envName = envChoice.name.trim();
  const dbName = `${prefix.trim()}_db`;
  const backupDir = path.resolve(`./local-backups_espejados/${prefix.trim()}`);
  const filename = `bkp_${prefix.trim()}_${envName}_${FECHA}`

  if (!fs.existsSync(backupDir)) fs.mkdirSync(backupDir, { recursive: true });

  try {
    const dumpFilePath = await backupDatabase({
      host: envChoice.host,          
      port: envChoice.port,          
      user: localConfig.usuario_backup,
      dbName,
      rutaPgDump: localConfig.ruta_pg_dump,
      backupDir,
      filename
    });

    const zipPath = await compressBackup(dumpFilePath);
    fs.unlinkSync(dumpFilePath); // elimina el .sql original

    console.log(`\n🎉 Backup finalizado con éxito:\n${zipPath}`);
  } catch (err) {
    console.error(`\n❌ Error durante el backup: ${err.message}`);
    process.exit(1);
  }
}

main();
