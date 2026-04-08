// run_all.js
// ---------------------------------------------------------------
// Ejecuta get_databases.js → backup_databases.js → store_feedback.js
// Cada script se ejecuta con Node y se espera a que finalice.
// ---------------------------------------------------------------

const { exec } = require('child_process');
const path = require('path');

// Helper que devuelve una promesa que se resuelve cuando el proceso termina
function runScript(scriptName) {
  const scriptPath = path.resolve(__dirname, scriptName);
  return new Promise((resolve, reject) => {
    console.log(`▶️  Iniciando ${scriptName}...`);
    exec(`node "${scriptPath}"`, { windowsHide: true }, (error, stdout, stderr) => {
      if (error) {
        console.error(`❌  ${scriptName} falló:`, error.message);
        reject(error);
        return;
      }
      if (stderr) {
        console.warn(`⚠️  ${scriptName} generó warnings:\n${stderr}`);
      }
      console.log(`✅  ${scriptName} completado.\n${stdout}`);
      resolve();
    });
  });
}

// Secuencia principal
(async () => {
  try {
    await runScript('get_databases.js');
    await runScript('backup_databases.js');
    await runScript('store_feedback.js');
    console.log('🎉  Todos los scripts se ejecutaron con éxito.');
  } catch (e) {
    console.error('🚨  Proceso interrumpido por error.');
    process.exit(1);
  }
})();
