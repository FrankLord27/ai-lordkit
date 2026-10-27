#!/usr/bin/env node
// brechas: cruza las dependencias del proyecto con avisos públicos y gratis.
//   OSV.dev  → vulnerabilidades (incluye GitHub Advisory Database) y paquetes maliciosos (MAL-*)
//   CISA KEV → CVE que se están explotando ya
//   EPSS     → probabilidad de explotación (FIRST.org)
// Solo salen nombres y versiones de paquetes públicos. Sin dependencias: Node 24 y fetch nativo.
//
// Uso: brechas.mjs [carpeta-del-proyecto] [--salida <dir>] [--excluir <patrón>]... [--sin-mcp] [--sin-claude] [--json]
// Salida: 0 sin críticos ni altos · 1 hay críticos o altos · 2 error de uso · 3 alguna fuente falló (reporte incompleto)

import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { basename, join, resolve } from 'node:path';
import { execFileSync } from 'node:child_process';

const OSV = 'https://api.osv.dev/v1';
const KEV_URL = 'https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json';
const EPSS_URL = 'https://api.first.org/data/v1/epss';
const EPSS_ALTO = 0.1;
const FIXTURES = process.env.BRECHAS_FIXTURES; // solo tests: respuestas grabadas en vez de red
const CACHE = join(process.env.XDG_CACHE_HOME || join(homedir(), '.cache'), 'ai-lordkit', 'brechas');
const SALTAR_DIRS = new Set(['node_modules', '.git', 'dist', 'build', '.next', 'coverage', '.turbo', '.pnpm-store']);
const SEMVER = /^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?/;

// ─── argumentos ─────────────────────────────────────────────────────────────
function leerArgs(argv) {
  const o = { dir: '.', salida: null, excluir: [], mcp: true, claude: true, json: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--salida') o.salida = argv[++i];
    else if (a === '--excluir') o.excluir.push(argv[++i]);
    else if (a === '--sin-mcp') o.mcp = false;
    else if (a === '--sin-claude') o.claude = false;
    else if (a === '--json') o.json = true;
    else if (a === '-h' || a === '--help') { ayuda(); process.exit(0); }
    else if (a.startsWith('-')) { console.error(`Opción desconocida: ${a}`); ayuda(); process.exit(2); }
    else o.dir = a;
  }
  if (o.excluir.some((p) => !p) || (o.salida === undefined)) { ayuda(); process.exit(2); }
  return o;
}

function ayuda() {
  console.error('Uso: brechas.mjs [carpeta] [--salida <dir>] [--excluir <patrón>]... [--sin-mcp] [--sin-claude] [--json]');
}

// ─── semver mínimo ─────────────────────────────────────────────────────────
function cmp(a, b) {
  const x = SEMVER.exec(a), y = SEMVER.exec(b);
  if (!x || !y) return 0;
  for (let i = 1; i <= 3; i++) {
    const d = Number(x[i]) - Number(y[i]);
    if (d) return Math.sign(d);
  }
  if (x[4] === y[4]) return 0;
  if (!x[4]) return 1; // 1.0.0 > 1.0.0-beta
  if (!y[4]) return -1;
  return x[4] < y[4] ? -1 : 1;
}

// ─── lockfiles ─────────────────────────────────────────────────────────────
function leerLockfile(dir) {
  const pnpm = join(dir, 'pnpm-lock.yaml');
  if (existsSync(pnpm)) return { archivo: 'pnpm-lock.yaml', ...leerPnpmLock(readFileSync(pnpm, 'utf8')) };
  const npm = join(dir, 'package-lock.json');
  if (existsSync(npm)) return { archivo: 'package-lock.json', ...leerNpmLock(JSON.parse(readFileSync(npm, 'utf8'))) };
  for (const otro of ['yarn.lock', 'bun.lock', 'bun.lockb']) {
    if (existsSync(join(dir, otro))) throw new Error(`${otro} todavía no está soportado (solo pnpm-lock.yaml y package-lock.json)`);
  }
  throw new Error(`no hay pnpm-lock.yaml ni package-lock.json en ${dir}`);
}

// pnpm v5, v6 y v9: las llaves de "packages:" son nombre@versión (v5: /nombre/versión), con sufijos de peers.
function leerPnpmLock(texto) {
  const paquetes = new Map();
  const raros = new Set();
  let enPackages = false;
  for (const linea of texto.split(/\r?\n/)) {
    if (/^\S/.test(linea)) { enPackages = /^packages:/.test(linea); continue; }
    if (!enPackages) continue;
    const m = /^ {2}['"]?\/?((?:@[^@/\s'"]+\/)?[^@/\s'"(]+)[@/]([^\s'"]+?)['"]?:\s*(\{.*)?$/.exec(linea);
    if (!m) continue;
    const v = SEMVER.exec(m[2]);
    if (v) agregar(paquetes, m[1], v[0]);
    else raros.add(`${m[1]}@${m[2]}`);
  }
  return { paquetes, raros };
}

function leerNpmLock(json) {
  const paquetes = new Map();
  const raros = new Set();
  if (!json.packages) throw new Error('package-lock.json v1 no está soportado: regenéralo con npm 7 o más nuevo');
  for (const [ruta, p] of Object.entries(json.packages)) {
    if (!ruta || p.link) continue;
    const nombre = p.name || ruta.slice(ruta.lastIndexOf('node_modules/') + 'node_modules/'.length);
    if (p.version && SEMVER.test(p.version)) agregar(paquetes, nombre, SEMVER.exec(p.version)[0]);
    else raros.add(`${nombre}@${p.version ?? '?'}`);
  }
  return { paquetes, raros };
}

function agregar(mapa, nombre, version) {
  if (!mapa.has(nombre)) mapa.set(nombre, new Set());
  mapa.get(nombre).add(version);
}

// Paquetes propios (workspace) no se consultan: su nombre no debe salir de la máquina.
function paquetesPropios(dir, prof = 0, nombres = new Set()) {
  if (prof > 6) return nombres;
  let entradas;
  try { entradas = readdirSync(dir, { withFileTypes: true }); } catch { return nombres; }
  for (const e of entradas) {
    if (e.isDirectory() && !SALTAR_DIRS.has(e.name) && !e.name.startsWith('.')) paquetesPropios(join(dir, e.name), prof + 1, nombres);
    else if (e.isFile() && e.name === 'package.json') {
      try {
        const n = JSON.parse(readFileSync(join(dir, e.name), 'utf8')).name;
        if (n) nombres.add(n);
      } catch { /* package.json roto: no aporta nombre */ }
    }
  }
  return nombres;
}

function coincide(nombre, patron) {
  if (patron.endsWith('*')) return nombre.startsWith(patron.slice(0, -1));
  return nombre === patron;
}

// ─── MCP y Claude Code ─────────────────────────────────────────────────────
// Solo se leen command/args; env y headers (donde viven los tokens) ni se tocan.
function archivosMcp(dir) {
  const kit = process.env.AI_LORDKIT_DIR || join(homedir(), '.ai-lordkit');
  const privado = process.env.AI_LORDKIT_PRIVATE || join(homedir(), 'ai-lordkit-private');
  return [join(dir, '.mcp.json'), join(kit, 'mcp', 'servers.json'), join(privado, 'mcp.json')].filter((f) => existsSync(f));
}

function paquetesMcp(archivos) {
  const lista = [];
  for (const f of archivos) {
    let servidores;
    try { servidores = JSON.parse(readFileSync(f, 'utf8')).mcpServers ?? {}; } catch { continue; }
    for (const [nombre, s] of Object.entries(servidores)) {
      const spec = specDeComando(s.command, Array.isArray(s.args) ? s.args : []);
      if (spec) lista.push({ servidor: nombre, archivo: f, ...spec });
    }
  }
  return lista;
}

function specDeComando(cmd, args) {
  const prog = basename(String(cmd ?? ''));
  let resto;
  if (['npx', 'pnpx', 'bunx'].includes(prog)) resto = args;
  else if (['pnpm', 'yarn'].includes(prog) && args[0] === 'dlx') resto = args.slice(1);
  else return null;
  for (let i = 0; i < resto.length; i++) {
    const a = String(resto[i]);
    if (a === '-p' || a === '--package') return parseSpec(String(resto[i + 1] ?? ''));
    if (a.startsWith('--package=')) return parseSpec(a.slice('--package='.length));
    if (!a.startsWith('-')) return parseSpec(a);
  }
  return null;
}

function parseSpec(spec) {
  if (!spec || /^[./~]/.test(spec) || spec.includes(':')) return null;
  const at = spec.indexOf('@', spec.startsWith('@') ? 1 : 0);
  const nombre = at === -1 ? spec : spec.slice(0, at);
  const pedido = at === -1 ? '' : spec.slice(at + 1);
  const v = SEMVER.exec(pedido);
  return { nombre, version: v && v[0] === pedido ? pedido : null, pedido };
}

function versionClaude() {
  try {
    const out = execFileSync('claude', ['--version'], { encoding: 'utf8', timeout: 10000, stdio: ['ignore', 'pipe', 'ignore'] });
    return SEMVER.exec(out.trim().split(/\s+/)[0])?.[0] ?? null;
  } catch { return null; }
}

// ─── red (o fixtures en tests) ─────────────────────────────────────────────
async function pedir(url, opciones = {}) {
  if (FIXTURES) {
    if (url.endsWith('/querybatch')) return osvFixture(JSON.parse(opciones.body));
    const f = join(FIXTURES, nombreFixture(url));
    if (!existsSync(f)) throw new Error(`sin respuesta (${nombreFixture(url)})`);
    return JSON.parse(readFileSync(f, 'utf8'));
  }
  const r = await fetch(url, { ...opciones, signal: AbortSignal.timeout(30000) });
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  return r.json();
}

// Tests: osv-db.json = { "nombre@versión" | "nombre": [{ id, modified }] }; lo enviado queda en enviado.json.
function osvFixture(body) {
  const f = join(FIXTURES, 'osv-db.json');
  if (!existsSync(f)) throw new Error('sin respuesta (osv-db.json)');
  const db = JSON.parse(readFileSync(f, 'utf8'));
  writeFileSync(join(FIXTURES, 'enviado.json'), JSON.stringify(body.queries));
  return {
    results: body.queries.map((q) => {
      const vulns = db[q.version ? `${q.package.name}@${q.version}` : q.package.name] ?? [];
      return vulns.length ? { vulns } : {};
    }),
  };
}

function nombreFixture(url) {
  if (url.includes('/v1/vulns/')) return `osv-vuln-${url.split('/').pop()}.json`;
  if (url === KEV_URL) return 'kev.json';
  if (url.startsWith(EPSS_URL)) return 'epss.json';
  return 'desconocido.json';
}

function cacheLeer(nombre, maxHoras) {
  if (FIXTURES) return null;
  const f = join(CACHE, nombre);
  try {
    const { guardado, datos } = JSON.parse(readFileSync(f, 'utf8'));
    if (maxHoras === Infinity || Date.now() - guardado < maxHoras * 3600e3) return datos;
  } catch { /* sin cache */ }
  return null;
}

function cacheGuardar(nombre, datos) {
  if (FIXTURES) return;
  try {
    mkdirSync(CACHE, { recursive: true });
    writeFileSync(join(CACHE, nombre), JSON.stringify({ guardado: Date.now(), datos }));
  } catch { /* sin cache no pasa nada */ }
}

async function enParalelo(items, n, fn) {
  const res = new Array(items.length);
  let i = 0;
  await Promise.all(Array.from({ length: Math.min(n, items.length) }, async () => {
    while (i < items.length) { const k = i++; res[k] = await fn(items[k]); }
  }));
  return res;
}

// ─── fuentes ───────────────────────────────────────────────────────────────
async function osvBatch(consultas) {
  const ids = consultas.map(() => []);
  for (let i = 0; i < consultas.length; i += 1000) {
    const lote = consultas.slice(i, i + 1000);
    const body = JSON.stringify({
      queries: lote.map((c) => ({ package: { name: c.nombre, ecosystem: 'npm' }, ...(c.version ? { version: c.version } : {}) })),
    });
    const r = await pedir(`${OSV}/querybatch`, { method: 'POST', body, headers: { 'content-type': 'application/json' } });
    (r.results ?? []).forEach((res, k) => { ids[i + k] = res.vulns ?? []; });
  }
  return ids;
}

async function osvDetalle(id, modificado) {
  const llave = `osv-${id}.json`;
  const c = cacheLeer(llave, Infinity);
  if (c && c.modified === modificado) return c;
  const d = await pedir(`${OSV}/vulns/${encodeURIComponent(id)}`);
  cacheGuardar(llave, d);
  return d;
}

async function kev() {
  let d = cacheLeer('kev.json', 24);
  if (!d) { d = await pedir(KEV_URL); cacheGuardar('kev.json', d); }
  return new Set((d.vulnerabilities ?? []).map((v) => v.cveID));
}

async function epss(cves) {
  const m = new Map();
  for (let i = 0; i < cves.length; i += 50) {
    const lote = cves.slice(i, i + 50);
    const d = await pedir(`${EPSS_URL}?cve=${lote.join(',')}`);
    for (const x of d.data ?? []) m.set(x.cve, Number(x.epss));
  }
  return m;
}

// ─── análisis ──────────────────────────────────────────────────────────────
function versionArreglada(v, nombre, version) {
  if (!version) return null;
  for (const a of v.affected ?? []) {
    if (a.package?.ecosystem !== 'npm' || a.package?.name !== nombre) continue;
    for (const r of a.ranges ?? []) {
      let desde = null;
      for (const e of r.events ?? []) {
        if (e.introduced !== undefined) desde = e.introduced === '0' ? '0.0.0' : e.introduced;
        else if (e.fixed !== undefined) {
          if (desde !== null && cmp(version, desde) >= 0 && cmp(version, e.fixed) < 0) return e.fixed;
          desde = null;
        } else if (e.last_affected !== undefined) desde = null;
      }
    }
  }
  return null;
}

function cvesDe(v) {
  return [v.id, ...(v.aliases ?? [])].filter((x) => /^CVE-\d{4}-\d+$/.test(x));
}

function clasificar(h, enKev, puntaje) {
  const razones = [];
  let nivel;
  if (h.id.startsWith('MAL-')) { nivel = 'critico'; razones.push('paquete malicioso (OpenSSF)'); }
  if (h.cves.some((c) => enKev.has(c))) { nivel = 'critico'; razones.push('se está explotando (CISA KEV)'); }
  const sev = (h.severidad || '').toUpperCase();
  const e = Math.max(0, ...h.cves.map((c) => puntaje.get(c) ?? 0));
  if (e > 0) razones.push(`EPSS ${(e * 100).toFixed(1)}%`);
  if (sev) razones.push(`severidad ${sev}`);
  if (!nivel) {
    if (sev === 'CRITICAL' || sev === 'HIGH' || e >= EPSS_ALTO) nivel = 'alto';
    else if (sev === 'MODERATE' || sev === 'MEDIUM') nivel = 'medio';
    else nivel = 'bajo';
  }
  return { ...h, nivel, razones, epss: e || null };
}

function leerIgnorados(dir) {
  const f = join(dir, '.brechas-ignorar');
  const m = new Map();
  if (!existsSync(f)) return m;
  for (const linea of readFileSync(f, 'utf8').split(/\r?\n/)) {
    const [id, ...motivo] = linea.replace(/^\s+/, '').split('#');
    const limpio = id.trim();
    if (limpio) m.set(limpio, motivo.join('#').trim() || 'sin motivo escrito');
  }
  return m;
}

// ─── reporte ───────────────────────────────────────────────────────────────
const NIVELES = [
  ['critico', 'Crítico: arreglar hoy'],
  ['alto', 'Alto'],
  ['medio', 'Medio'],
  ['bajo', 'Bajo o sin severidad'],
];

function celda(s) { return String(s ?? '').replace(/\|/g, '\\|').replace(/\r?\n/g, ' '); }

function markdown(r) {
  const l = [];
  l.push(`# Brechas en ${r.proyecto}: ${r.fecha}`, '');
  l.push(`Revisado: ${r.revisado.paquetes} versiones de paquetes en \`${r.revisado.lockfile}\`, ${r.revisado.mcp} servidores MCP, Claude Code ${r.revisado.claude ?? 'no revisado'}.`);
  l.push('Fuentes: [OSV.dev](https://osv.dev) (incluye GitHub Advisory Database y paquetes maliciosos de OpenSSF), [CISA KEV](https://www.cisa.gov/known-exploited-vulnerabilities-catalog) y [EPSS](https://www.first.org/epss/).', '');
  if (r.fallas.length) {
    l.push('> **Reporte incompleto.** Estas fuentes fallaron:');
    for (const f of r.fallas) l.push(`> - ${f}`);
    l.push('');
  }
  l.push('| Nivel | Hallazgos |', '|---|---|');
  for (const [k, t] of NIVELES) l.push(`| ${t} | ${r.hallazgos.filter((h) => h.nivel === k).length} |`);
  l.push('');
  for (const [k, t] of NIVELES) {
    const hs = r.hallazgos.filter((h) => h.nivel === k);
    if (!hs.length) continue;
    l.push(`## ${t}`, '', '| Aviso | Paquete | Tu versión | Arreglo | Por qué | Origen | Resumen |', '|---|---|---|---|---|---|---|');
    for (const h of hs) {
      l.push(`| [${h.id}](https://osv.dev/vulnerability/${h.id}) | \`${h.paquete}\` | ${h.version ?? 'sin fijar'} | ${h.arreglo ?? '—'} | ${celda(h.razones.join('; '))} | ${celda(h.origen)} | ${celda(h.resumen)} |`);
    }
    l.push('');
  }
  if (!r.hallazgos.length && !r.fallas.length) l.push('Sin avisos conocidos para estas versiones hoy. Eso no garantiza que no haya fallos todavía sin publicar.', '');
  if (r.ignorados.length) {
    l.push('## Ignorados (`.brechas-ignorar`)', '');
    for (const h of r.ignorados) l.push(`- ${h.id} en \`${h.paquete}@${h.version ?? '?'}\`: ${h.motivo}`);
    l.push('');
  }
  if (r.noVerificados.length || r.mcpSinVersion.length) {
    l.push('## No verificado', '');
    if (r.mcpSinVersion.length) l.push(`- Servidores MCP sin versión fijada (solo se buscó si el paquete es malicioso; fija la versión para revisarlos completos): ${r.mcpSinVersion.map((m) => `\`${m}\``).join(', ')}`);
    if (r.noVerificados.length) l.push(`- Dependencias sin versión de npm (git, archivo o tarball): ${r.noVerificados.slice(0, 30).map((m) => `\`${m}\``).join(', ')}${r.noVerificados.length > 30 ? ` y ${r.noVerificados.length - 30} más` : ''}`);
    l.push('');
  }
  return l.join('\n');
}

// ─── principal ─────────────────────────────────────────────────────────────
async function main() {
  const o = leerArgs(process.argv.slice(2));
  const dir = resolve(o.dir);
  const fecha = new Date().toISOString().slice(0, 10);
  const fallas = [];

  let lock;
  try { lock = leerLockfile(dir); } catch (e) { console.error(`brechas: ${e.message}`); process.exit(2); }

  const propios = paquetesPropios(dir);
  const excluido = (n) => propios.has(n) || o.excluir.some((p) => coincide(n, p));

  // consultas: [{nombre, version|null, origen}]
  const consultas = [];
  for (const [nombre, versiones] of lock.paquetes) {
    if (excluido(nombre)) continue;
    for (const version of versiones) consultas.push({ nombre, version, origen: 'lockfile' });
  }
  const totalLock = consultas.length;

  const mcpSinVersion = [];
  let nMcp = 0;
  if (o.mcp) {
    for (const m of paquetesMcp(archivosMcp(dir))) {
      if (excluido(m.nombre)) continue;
      nMcp++;
      consultas.push({ nombre: m.nombre, version: m.version, origen: `MCP ${m.servidor}`, soloMal: !m.version });
      if (!m.version) mcpSinVersion.push(`${m.servidor} (${m.nombre}${m.pedido ? `@${m.pedido}` : ''})`);
    }
  }
  const claude = o.claude ? versionClaude() : null;
  if (claude) consultas.push({ nombre: '@anthropic-ai/claude-code', version: claude, origen: 'Claude Code' });

  let ids = [];
  try { ids = await osvBatch(consultas); } catch (e) { fallas.push(`OSV.dev: ${e.message}`); }

  // detalle de cada aviso (único por id)
  const unicos = new Map();
  ids.forEach((vs, i) => vs.forEach((v) => {
    if (!consultas[i].soloMal || v.id.startsWith('MAL-')) unicos.set(v.id, v.modified);
  }));
  const detalles = new Map();
  let fallosDetalle = 0;
  await enParalelo([...unicos], 8, async ([id, mod]) => {
    try { detalles.set(id, await osvDetalle(id, mod)); } catch { fallosDetalle++; }
  });
  if (fallosDetalle) fallas.push(`OSV.dev: no se pudo leer el detalle de ${fallosDetalle} avisos`);

  const crudos = [];
  consultas.forEach((c, i) => {
    const vistos = new Set();
    for (const { id } of ids[i] ?? []) {
      if (c.soloMal && !id.startsWith('MAL-')) continue;
      const v = detalles.get(id) ?? { id };
      if (v.withdrawn || vistos.has(id)) continue;
      [id, ...(v.aliases ?? [])].forEach((x) => vistos.add(x));
      crudos.push({
        id,
        paquete: c.nombre,
        version: c.version,
        origen: c.origen,
        arreglo: versionArreglada(v, c.nombre, c.version),
        severidad: v.database_specific?.severity ?? null,
        cves: cvesDe(v),
        resumen: v.summary ?? (v.details ? v.details.slice(0, 140) : ''),
      });
    }
  });

  let enKev = new Set();
  if (crudos.some((h) => h.cves.length)) {
    try { enKev = await kev(); } catch (e) { fallas.push(`CISA KEV: ${e.message}`); }
  }
  let puntaje = new Map();
  const cves = [...new Set(crudos.flatMap((h) => h.cves))];
  if (cves.length) {
    try { puntaje = await epss(cves); } catch (e) { fallas.push(`EPSS: ${e.message}`); }
  }

  const ignorar = leerIgnorados(dir);
  const orden = { critico: 0, alto: 1, medio: 2, bajo: 3 };
  const hallazgos = [];
  const ignorados = [];
  for (const h of crudos.map((x) => clasificar(x, enKev, puntaje))) {
    const clave = [h.id, ...h.cves].find((x) => ignorar.has(x));
    // Un paquete malicioso no se puede ignorar: no hay "riesgo aceptado" con malware.
    if (clave && !h.id.startsWith('MAL-')) ignorados.push({ ...h, motivo: ignorar.get(clave) });
    else hallazgos.push(h);
  }
  const mal = (h) => (h.id.startsWith('MAL-') ? 0 : 1);
  hallazgos.sort((a, b) => orden[a.nivel] - orden[b.nivel] || mal(a) - mal(b) || (b.epss ?? 0) - (a.epss ?? 0) || a.paquete.localeCompare(b.paquete));

  const reporte = {
    proyecto: basename(dir),
    fecha,
    revisado: { lockfile: lock.archivo, paquetes: totalLock, mcp: nMcp, claude },
    fallas,
    hallazgos,
    ignorados,
    mcpSinVersion,
    noVerificados: [...lock.raros].filter((x) => !excluido(x.slice(0, x.lastIndexOf('@')))),
  };

  const salida = resolve(o.salida ?? join(dir, 'docs', 'seguridad'));
  mkdirSync(salida, { recursive: true });
  const base = join(salida, `brechas-${fecha}`);
  writeFileSync(`${base}.json`, `${JSON.stringify(reporte, null, 2)}\n`);
  writeFileSync(`${base}.md`, `${markdown(reporte)}\n`);

  const n = (k) => hallazgos.filter((h) => h.nivel === k).length;
  if (o.json) process.stdout.write(`${JSON.stringify(reporte, null, 2)}\n`);
  else {
    console.log(`brechas: ${totalLock} versiones (${lock.archivo}), ${nMcp} MCP, Claude Code ${claude ?? 'no revisado'}`);
    console.log(`crítico ${n('critico')} · alto ${n('alto')} · medio ${n('medio')} · bajo ${n('bajo')} · ignorados ${ignorados.length}`);
    for (const f of fallas) console.log(`FUENTE FALLÓ: ${f}`);
    console.log(`reporte: ${base}.md`);
  }
  if (n('critico') || n('alto')) process.exit(1);
  if (fallas.length) process.exit(3);
}

main().catch((e) => { console.error(`brechas: ${e.stack || e.message}`); process.exit(3); });
