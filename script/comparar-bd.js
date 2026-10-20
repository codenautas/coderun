#!/usr/bin/env node
'use strict';
// Compara una base existente (por ejemplo el backup de producción restaurado) contra una base de referencia (el esquema que
// espera el código, armado a cero) y escribe el script SQL con las diferencias. El script se puede correr más de una vez.
//
// Solo compara estructura: tablas, columnas y tipos, restricciones, funciones (por cuerpo), triggers, y copia los datos de las
// tablas que se indiquen en --datos. Lo que dependa de los datos (columnas not null sin valor por defecto, conversiones de tipo
// con reglas propias) queda marcado en el script para completarlo a mano.
//
// Uso: comparar-bd.js --referencia <base> --origen <base> --admin <usuario> [opciones]
//   --referencia  base con el esquema esperado (por ejemplo la que se carga con `npm start -- --dump-db`)
//   --origen      base a actualizar (backup restaurado)
//   --admin       usuario de la aplicación, al que se le dan permisos sobre lo nuevo
//   --owner       owner de la base, solo para el comentario del encabezado (por defecto, el que va en --admin sin _admin + _owner)
//   --esquema     esquema principal de la aplicación (por defecto base)
//   --esquemas    esquemas de los que se comparan las funciones (por defecto base,comun,his)
//   --datos       tablas del esquema principal cuyas filas se copian de la referencia si no existen (separadas por coma)
//   --orden       tablas nuevas que se crean primero, en ese orden (separadas por coma); el resto va después
//   --salida      archivo a escribir (por defecto, la salida estándar)
//   --host --puerto --usuario   conexión; la contraseña va en PGPASSWORD
// Hace falta psql y pg_dump en el PATH (o en las variables PSQL y PG_DUMP). No usa ningún módulo.

const fs = require('fs');
const { execFileSync } = require('child_process');

function leerOpciones(argv) {
    const o = {};
    for (let i = 0; i < argv.length; i++) {
        const m = /^--(.+)$/.exec(argv[i]);
        if (!m) throw new Error('parámetro inesperado: ' + argv[i]);
        o[m[1]] = argv[++i];
    }
    return o;
}
const opciones = leerOpciones(process.argv.slice(2));
for (const obligatoria of ['referencia', 'origen', 'admin']) {
    if (!opciones[obligatoria]) {
        console.error('Falta --' + obligatoria + '. Ver el encabezado de ' + process.argv[1]);
        process.exit(1);
    }
}
const lista = valor => (valor || '').split(',').map(s => s.trim()).filter(Boolean);
const ESQUEMA = opciones.esquema || 'base';
const ESQUEMAS = lista(opciones.esquemas || 'base,comun,his');
const DATOS = lista(opciones.datos);
const ORDEN = lista(opciones.orden);
const ADMIN = opciones.admin;
const OWNER = opciones.owner || ADMIN.replace(/_admin$/, '') + '_owner';
const PSQL = process.env.PSQL || 'psql';
const PG_DUMP = process.env.PG_DUMP || 'pg_dump';
const literal = valor => "'" + String(valor).replace(/'/g, "''") + "'";
const identificador = valor => '"' + String(valor).replace(/"/g, '""') + '"';

const conexion = [];
if (opciones.host) conexion.push('-h', opciones.host);
if (opciones.puerto) conexion.push('-p', opciones.puerto);
if (opciones.usuario) conexion.push('-U', opciones.usuario);

function consulta(base, sql) {
    const salida = execFileSync(PSQL, [...conexion, '-X', '-A', '-t', '-d', base, '-c',
        `select coalesce(json_agg(t), '[]'::json) from (${sql}) t`], { encoding: 'utf8', maxBuffer: 1 << 28 });
    return JSON.parse(salida);
}

const esquemaSql = literal(ESQUEMA);
const prefijo = new RegExp('^' + ESQUEMA.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '\\.');
const partes = [];
const titulo = t => partes.push(`\n-- ${'='.repeat(70)}\n-- ${t}\n-- ${'='.repeat(70)}\n`);
const REF = opciones.referencia, ORI = opciones.origen;

partes.push(`-- Diferencias de ${ORI} contra ${REF} (generado por coderun/script/comparar-bd.js el ${new Date().toISOString().slice(0, 10)}).
-- Correr con el owner de la base (${OWNER}). Se puede repetir.
-- Revisar a mano lo marcado "completar": la comparación solo ve la estructura.
--set role ${OWNER};
set search_path = ${ESQUEMA};
-- las funciones se crean antes que las tablas que las usan
set check_function_bodies = off;
`);

// 1. funciones
titulo('funciones nuevas o cambiadas (los esquemas de apoyo primero)');
const SQL_FUN = `select n.nspname, p.proname, pg_get_function_identity_arguments(p.oid) args, p.prokind,
        md5(regexp_replace(p.prosrc, '\\s+', ' ', 'g')) h, pg_get_functiondef(p.oid) def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in (${ESQUEMAS.map(literal).join(', ')}) and p.prokind in ('f', 'p')`;
const funRef = consulta(REF, SQL_FUN), funOri = consulta(ORI, SQL_FUN);
const claveFun = f => `${f.nspname}.${f.proname}(${f.args})`;
const hashOri = new Map(funOri.map(f => [claveFun(f), f.h]));
const distintas = funRef.filter(f => hashOri.get(claveFun(f)) !== f.h && f.nspname != 'his');
distintas.sort((a, b) => (a.nspname == ESQUEMA ? 1 : 0) - (b.nspname == ESQUEMA ? 1 : 0));
distintas.forEach(f => partes.push(`-- ${claveFun(f)}\n${f.def.trim()};\n`));
distintas.filter(f => f.nspname == ESQUEMA).forEach(f =>
    partes.push(`grant execute on ${f.prokind == 'p' ? 'procedure' : 'function'} ${f.nspname}.${f.proname}(${f.args}) to ${ADMIN};`));

// 2. obsoletos
const SQL_TABLAS = `select c.relname from pg_class c where c.relnamespace = ${esquemaSql}::regnamespace and c.relkind = 'r' order by 1`;
const tablasRef = consulta(REF, SQL_TABLAS).map(r => r.relname), tablasOri = new Set(consulta(ORI, SQL_TABLAS).map(r => r.relname));
const SQL_TRG = `select c.relname tabla, t.tgname, pg_get_triggerdef(t.oid) def from pg_trigger t join pg_class c on c.oid = t.tgrelid
    where not t.tgisinternal and c.relnamespace = ${esquemaSql}::regnamespace`;
const trgRef = consulta(REF, SQL_TRG), trgOri = consulta(ORI, SQL_TRG);
titulo('obsoletos (funciones que el código ya no tiene)');
const funObsoletas = funOri.filter(f => !funRef.some(g => claveFun(g) == claveFun(f)) && f.nspname == ESQUEMA);
// un trigger que ya no está en la referencia se borra antes que su función
const trgRefClaves = new Set(trgRef.map(t => `${t.tabla}.${t.tgname}`));
trgOri.filter(t => tablasRef.includes(t.tabla) && !trgRefClaves.has(`${t.tabla}.${t.tgname}`))
    .forEach(t => partes.push(`drop trigger if exists ${t.tgname} on ${t.tabla};`));
funObsoletas.forEach(f => partes.push(`drop function if exists ${f.nspname}.${f.proname}(${f.args});`));

// 3. secuencias nuevas (antes que las tablas: los valores por defecto las usan, y no todas pertenecen a una tabla)
titulo('secuencias nuevas');
const SQL_SEC = `select schemaname || '.' || sequencename as nombre, data_type::text as tipo, start_value::text, min_value::text, max_value::text, increment_by::text, cycle, cache_size::text
    from pg_sequences where schemaname in (${ESQUEMAS.map(literal).join(', ')}) order by 1`;
const secOri = new Set(consulta(ORI, SQL_SEC).map(q => q.nombre));
consulta(REF, SQL_SEC).filter(q => !secOri.has(q.nombre)).forEach(q => partes.push(
    `create sequence if not exists ${q.nombre} as ${q.tipo} increment by ${q.increment_by} minvalue ${q.min_value} maxvalue ${q.max_value} start with ${q.start_value} cache ${q.cache_size}${q.cycle ? ' cycle' : ''};`));

// 3b. tablas nuevas
titulo('tablas nuevas (de pg_dump -s de la referencia)');
const nuevas = tablasRef.filter(t => !tablasOri.has(t));
// tablas nuevas de los esquemas de apoyo (por ejemplo his.bitacora): se crean con el nombre completo
const SQL_TABLAS_APOYO = `select n.nspname || '.' || c.relname as nombre from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname in (${ESQUEMAS.filter(e => e != ESQUEMA).map(literal).join(', ') || 'null'}) and c.relkind = 'r' order by 1`;
const apoyoOri = new Set(consulta(ORI, SQL_TABLAS_APOYO).map(r => r.nombre));
const nuevasApoyo = consulta(REF, SQL_TABLAS_APOYO).map(r => r.nombre).filter(t => !apoyoOri.has(t));
const posicion = t => ORDEN.indexOf(t) < 0 ? 1e6 : ORDEN.indexOf(t);
nuevas.sort((a, b) => posicion(a) - posicion(b));
const crear = [], fks = [];
for (const t of [...nuevasApoyo, ...nuevas.map(t => `${ESQUEMA}.${t}`)]) {
    const dump = execFileSync(PG_DUMP, [...conexion, '-d', REF, '-s', '-t', t, '--no-owner', '--no-privileges'], { encoding: 'utf8' });
    const sentencias = dump.split(/\n(?=CREATE |ALTER |COMMENT )/).map(s => s.trim()).filter(s => /^(CREATE|ALTER)/.test(s));
    sentencias.forEach(s => {
        const sql = s.replace(/^--.*$/gm, '').replace(/\n--[^\n]*$/g, '').trim().replace(/;+\s*$/, '');
        if (/FOREIGN KEY/.test(sql)) fks.push(sql);
        else if (/^CREATE TABLE/.test(sql)) crear.push(sql.replace(/^CREATE TABLE/, 'CREATE TABLE IF NOT EXISTS'));
        else if (/^CREATE SEQUENCE/.test(sql)) crear.push(sql.replace(/^CREATE SEQUENCE/, 'CREATE SEQUENCE IF NOT EXISTS'));
        else if (/^CREATE (UNIQUE )?INDEX/.test(sql)) crear.push(sql.replace(/^CREATE (UNIQUE )?INDEX/, 'CREATE $1INDEX IF NOT EXISTS'));
        else crear.push(sql);
    });
}
// alter ... add constraint no se puede repetir: se protege con un bloque do
const idempotente = sql => {
    const m = sql.match(/^ALTER TABLE (?:ONLY )?(\S+)\s+ADD CONSTRAINT ("(?:[^"]|"")+"|\S+)/s);
    if (!m) return sql + ';';
    return `do $$ begin if not exists (select 1 from pg_constraint where conrelid = ${literal(m[1])}::regclass and conname = ${literal(m[2].replace(/^"|"$/g, ''))}) then ${sql}; end if; end $$;`;
};
crear.forEach(s => partes.push(/^ALTER TABLE/.test(s) ? idempotente(s)
    : (/^CREATE TRIGGER/.test(s) ? `drop trigger if exists ${s.match(/^CREATE TRIGGER (\S+)/)[1]} on ${s.match(/ ON (\S+)/)[1]};\n${s};` : s + ';')));

// 4. columnas nuevas en tablas que ya existen
titulo('columnas nuevas en tablas existentes');
const SQL_COL = `select c.relname tabla, a.attname col, format_type(a.atttypid, a.atttypmod) tipo, a.attnotnull nn, pg_get_expr(d.adbin, d.adrelid) def
    from pg_attribute a join pg_class c on c.oid = a.attrelid left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
    where c.relnamespace = ${esquemaSql}::regnamespace and c.relkind = 'r' and a.attnum > 0 and not a.attisdropped`;
const colRef = consulta(REF, SQL_COL), colOri = consulta(ORI, SQL_COL);
const existeCol = new Set(colOri.map(c => `${c.tabla}.${c.col}`));
for (const c of colRef.filter(c => tablasOri.has(c.tabla) && !existeCol.has(`${c.tabla}.${c.col}`))) {
    // not null solo si tiene valor por defecto (las filas que ya existen lo toman); si no, se completa a mano
    partes.push(`alter table ${c.tabla} add column if not exists ${identificador(c.col)} ${c.tipo}${c.def ? ` default ${c.def}` : ''}${c.nn && c.def ? ' not null' : ''};${c.nn && !c.def ? ' -- en la referencia es not null: completar y fijarlo' : ''}`);
}

// 4b. columnas que cambiaron de tipo
titulo('columnas que cambiaron de tipo (el cast puede necesitar una regla propia: completar)');
const tipoOri = new Map(colOri.map(c => [`${c.tabla}.${c.col}`, c.tipo]));
for (const c of colRef.filter(c => tablasOri.has(c.tabla) && tipoOri.has(`${c.tabla}.${c.col}`) && tipoOri.get(`${c.tabla}.${c.col}`) != c.tipo)) {
    partes.push(`alter table ${c.tabla} alter column ${identificador(c.col)} type ${c.tipo} using ${identificador(c.col)}::${c.tipo};`);
}

// datos básicos que traen las tablas indicadas (los que ya existen no se tocan)
titulo('datos básicos');
for (const tabla of DATOS) {
    const filas = consulta(REF, `select * from ${ESQUEMA}.${identificador(tabla)}`);
    if (!filas.length) continue;
    const columnas = Object.keys(filas[0]);
    const valores = filas.map(fila => '(' + columnas.map(c => fila[c] == null ? 'null' : literal(typeof fila[c] == 'object' ? JSON.stringify(fila[c]) : fila[c])).join(', ') + ')');
    partes.push(`insert into ${tabla} (${columnas.map(identificador).join(', ')}) values\n${valores.join(',\n')}\non conflict do nothing;`);
}

// 5. restricciones de tablas existentes
titulo('restricciones de tablas existentes');
const SQL_CON = `select conrelid::regclass::text tabla, conname, contype, pg_get_constraintdef(oid) def from pg_constraint where connamespace = ${esquemaSql}::regnamespace`;
const sinEsquema = t => t.replace(prefijo, '');
const conOri = new Set(consulta(ORI, SQL_CON).map(c => `${sinEsquema(c.tabla)}.${c.conname}`));
const ordenTipo = { c: 0, u: 1, p: 2, f: 3 };
const pendientes = consulta(REF, SQL_CON)
    .filter(c => tablasOri.has(sinEsquema(c.tabla)) && !conOri.has(`${sinEsquema(c.tabla)}.${c.conname}`) && c.contype != 'p')
    .sort((a, b) => ordenTipo[a.contype] - ordenTipo[b.contype]);
for (const c of pendientes) {
    partes.push(`do $$ begin if not exists (select 1 from pg_constraint where conrelid = ${literal(c.tabla)}::regclass and conname = ${literal(c.conname)}) then alter table ${c.tabla} add constraint ${identificador(c.conname)} ${c.def}; end if; end $$;`);
}
titulo('llaves foráneas de las tablas nuevas');
fks.forEach(s => partes.push(idempotente(s)));

// 6. triggers que faltan en tablas existentes
titulo('triggers de tablas existentes');
const trgOriClaves = new Set(trgOri.map(t => `${t.tabla}.${t.tgname}`));
for (const t of trgRef.filter(t => tablasOri.has(t.tabla) && !trgOriClaves.has(`${t.tabla}.${t.tgname}`))) {
    partes.push(`drop trigger if exists ${t.tgname} on ${t.tabla};\n${t.def};`);
}

// 7. permisos
titulo('permisos del usuario de la aplicación sobre lo que es del owner');
ESQUEMAS.forEach(e => partes.push(`grant usage on schema ${e} to ${ADMIN};`));
partes.push(`do $$
declare t record;
begin
    for t in select schemaname, tablename from pg_tables where schemaname in (${ESQUEMAS.filter(e => e != 'comun').map(literal).join(', ')}) and tableowner = current_user loop
        execute format('grant select, insert, update, delete on %I.%I to ${ADMIN}', t.schemaname, t.tablename);
    end loop;
    for t in select schemaname, sequencename from pg_sequences where schemaname in (${ESQUEMAS.filter(e => e != 'comun').map(literal).join(', ')}) and sequenceowner = current_user loop
        execute format('grant usage, select on sequence %I.%I to ${ADMIN}', t.schemaname, t.sequencename);
    end loop;
end
$$;`);

const texto = partes.join('\n') + '\n';
if (opciones.salida) fs.writeFileSync(opciones.salida, texto); else process.stdout.write(texto);
console.error(`funciones ${distintas.length} | obsoletas ${funObsoletas.length} | tablas nuevas ${nuevas.length + nuevasApoyo.length} | restricciones ${pendientes.length} | llaves foráneas ${fks.length}`);
