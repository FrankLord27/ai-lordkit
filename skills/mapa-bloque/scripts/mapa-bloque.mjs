#!/usr/bin/env node
// mapa-bloque: analiza una carpeta (un "bloque") de un proyecto TypeScript y genera
// un mapa interactivo de qué archivos tiene, qué conecta con qué y qué está sin usar.
// Todo sale del compilador de TypeScript, no de la IA: lo que dice el mapa es verificable.
//
// Uso: node mapa-bloque.mjs <carpeta-del-bloque> [--nombre login] [--salida docs/mapas] [--sin-tests]

import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const AQUI = path.dirname(fileURLToPath(import.meta.url));

// ---------- argumentos ----------
function leerArgs(argv) {
  const a = { bloque: null, nombre: null, salida: null, sinTests: false };
  for (let i = 0; i < argv.length; i++) {
    const v = argv[i];
    if (v === '--nombre') a.nombre = argv[++i];
    else if (v === '--salida') a.salida = argv[++i];
    else if (v === '--sin-tests') a.sinTests = true;
    else if (v === '-h' || v === '--help') a.ayuda = true;
    else if (!a.bloque) a.bloque = v;
  }
  return a;
}
const args = leerArgs(process.argv.slice(2));
if (args.ayuda || !args.bloque) {
  console.log(`Uso: node mapa-bloque.mjs <carpeta-del-bloque> [--nombre login] [--salida docs/mapas] [--sin-tests]

Genera en la carpeta de salida:
  <nombre>.html  mapa interactivo (ábrelo en el navegador)
  <nombre>.json  los datos crudos (para otra herramienta o para la IA)
  <nombre>.md    resumen con diagrama Mermaid (GitHub lo pinta en un PR)`);
  process.exit(args.bloque ? 0 : 1);
}

const bloqueAbs = path.resolve(args.bloque);
if (!fs.existsSync(bloqueAbs) || !fs.statSync(bloqueAbs).isDirectory()) {
  fallar(`No existe la carpeta ${args.bloque}`);
}

function fallar(msg) {
  console.error(`mapa-bloque: ${msg}`);
  process.exit(1);
}

// ---------- motor: TypeScript con API de JavaScript ----------
// TypeScript 7 (el compilador en Go) ya no expone createProgram, así que el script
// trae su propio TypeScript 6 en scripts/node_modules. Si no está, prueba el del proyecto.
function cargarTs(desde) {
  const candidatos = [path.join(AQUI, 'package.json'), path.join(desde, 'package.json')];
  for (const c of candidatos) {
    try {
      const ts = createRequire(c)('typescript');
      if (typeof ts.createProgram === 'function') return ts;
    } catch { /* sigue */ }
  }
  fallar(`falta el motor de análisis. Corre una vez:\n  pnpm install --frozen-lockfile --prod --ignore-scripts --dir "${AQUI}"`);
}

const ts = cargarTs(bloqueAbs);

// ---------- tsconfig ----------
const configPath = ts.findConfigFile(bloqueAbs, ts.sys.fileExists, 'tsconfig.json');
if (!configPath) fallar('no encontré un tsconfig.json en la carpeta ni más arriba.');
const proyectoDir = path.dirname(configPath);
const leido = ts.readConfigFile(configPath, ts.sys.readFile);
if (leido.error) fallar(`no pude leer ${configPath}`);
const parsed = ts.parseJsonConfigFileContent(leido.config, ts.sys, proyectoDir);
const opciones = {
  ...parsed.options,
  noEmit: true,
  noUnusedLocals: true,
  noUnusedParameters: true,
  skipLibCheck: true,
  incremental: false,
  composite: false,
  tsBuildInfoFile: undefined,
  ignoreDeprecations: '6.0',
};

const EXT = /\.(c|m)?(t|j)sx?$/;
const esFuente = (f) => EXT.test(f) && !/\.d\.(c|m)?ts$/.test(f) && !f.includes(`${path.sep}node_modules${path.sep}`);
const norm = (f) => path.resolve(f);
const dentroDe = (f, dir) => norm(f).startsWith(dir + path.sep);
// se mira la ruta relativa al proyecto para que carpetas de más arriba no confundan
const relP = (f) => path.sep + path.relative(proyectoDir, f);
const esTest = (f) => /\.(spec|test|e2e-spec|e2e)\.(t|j)sx?$/.test(f) || /[\\/](__tests__|test|tests)[\\/]/.test(relP(f));

// archivos del proyecto según tsconfig, más los del bloque aunque el tsconfig los excluya
const archivosProyecto = new Set(parsed.fileNames.filter(esFuente).map(norm));
function recorrer(dir, out) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.name === 'node_modules' || e.name.startsWith('.')) continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) recorrer(p, out);
    else if (esFuente(p)) out.push(norm(p));
  }
  return out;
}
let archivosBloque = recorrer(bloqueAbs, []);
if (args.sinTests) archivosBloque = archivosBloque.filter((f) => !esTest(f));
if (archivosBloque.length === 0) fallar('la carpeta no tiene archivos .ts/.tsx/.js.');
for (const f of archivosBloque) archivosProyecto.add(f);
const enBloque = new Set(archivosBloque);

// ---------- programa y diagnósticos ----------
const programa = ts.createProgram({ rootNames: archivosBloque, options: opciones });
const checker = programa.getTypeChecker();

// códigos de "declarado pero nunca usado"
const COD_SIN_USO = new Set([6133, 6138, 6192, 6196, 6198, 6199, 6205]);

// ---------- resolución de imports ----------
const cacheRes = new Map();
function resolver(spec, desde) {
  const k = `${desde}\0${spec}`;
  if (cacheRes.has(k)) return cacheRes.get(k);
  const r = ts.resolveModuleName(spec, desde, opciones, ts.sys).resolvedModule;
  let out;
  if (!r) out = { tipo: spec.startsWith('.') || spec.startsWith('/') ? 'roto' : 'paquete', id: spec.startsWith('.') ? spec : nombrePaquete(spec) };
  else if (r.isExternalLibraryImport || /[\\/]node_modules[\\/]/.test(r.resolvedFileName)) out = { tipo: 'paquete', id: nombrePaquete(spec) };
  else out = { tipo: 'archivo', id: norm(r.resolvedFileName.replace(/\.d\.(c|m)?ts$/, '.ts')) };
  if (out.tipo === 'archivo' && !fs.existsSync(out.id)) out.id = norm(r.resolvedFileName);
  cacheRes.set(k, out);
  return out;
}
function nombrePaquete(spec) {
  if (spec.startsWith('node:')) return 'node';
  const builtins = new Set(['fs', 'path', 'os', 'crypto', 'http', 'https', 'url', 'util', 'stream', 'events', 'child_process', 'zlib', 'buffer', 'assert', 'net', 'tls', 'dns', 'readline', 'worker_threads']);
  const base = spec.split('/')[0];
  if (builtins.has(base)) return 'node';
  return spec.startsWith('@') ? spec.split('/').slice(0, 2).join('/') : base;
}

// Extrae imports de un archivo: [{spec, nombres:[...], forma}]
function importsDe(sf) {
  const out = [];
  const nombresDe = (clause) => {
    if (!clause) return ['(efecto)'];
    const n = [];
    if (clause.name) n.push('default');
    const nb = clause.namedBindings;
    if (nb && ts.isNamespaceImport(nb)) n.push('*');
    if (nb && ts.isNamedImports(nb)) for (const e of nb.elements) n.push((e.propertyName ?? e.name).text);
    return n;
  };
  for (const st of sf.statements) {
    if (ts.isImportDeclaration(st) && ts.isStringLiteral(st.moduleSpecifier)) {
      out.push({ spec: st.moduleSpecifier.text, nombres: nombresDe(st.importClause), forma: 'import' });
    } else if (ts.isExportDeclaration(st) && st.moduleSpecifier && ts.isStringLiteral(st.moduleSpecifier)) {
      const n = !st.exportClause || ts.isNamespaceExport(st.exportClause) ? ['*'] : st.exportClause.elements.map((e) => (e.propertyName ?? e.name).text);
      out.push({ spec: st.moduleSpecifier.text, nombres: n, forma: 're-export' });
    } else if (ts.isImportEqualsDeclaration(st) && ts.isExternalModuleReference(st.moduleReference) && ts.isStringLiteral(st.moduleReference.expression)) {
      out.push({ spec: st.moduleReference.expression.text, nombres: ['*'], forma: 'import' });
    }
  }
  const texto = sf.text;
  if (texto.includes('import(') || texto.includes('require(')) {
    const visitar = (n) => {
      if (ts.isCallExpression(n) && n.arguments.length === 1 && ts.isStringLiteralLike(n.arguments[0])) {
        const dyn = n.expression.kind === ts.SyntaxKind.ImportKeyword;
        const req = ts.isIdentifier(n.expression) && n.expression.text === 'require';
        if (dyn || req) out.push({ spec: n.arguments[0].text, nombres: ['*'], forma: 'dinámico' });
      }
      ts.forEachChild(n, visitar);
    };
    visitar(sf);
  }
  return out;
}

function sourceDe(f) {
  return programa.getSourceFile(f) ?? ts.createSourceFile(f, fs.readFileSync(f, 'utf8'), ts.ScriptTarget.Latest, true, /x$/.test(f) ? ts.ScriptKind.TSX : undefined);
}

// ---------- índice de uso en todo el proyecto ----------
// usos.get(archivo) = Map(nombreExport -> Set(importadores))
const usos = new Map();
const importsPorArchivo = new Map();
for (const f of archivosProyecto) {
  let sf;
  try { sf = sourceDe(f); } catch { continue; }
  const imps = importsDe(sf).map((i) => ({ ...i, destino: resolver(i.spec, f) }));
  importsPorArchivo.set(f, imps);
  for (const i of imps) {
    if (i.destino.tipo !== 'archivo') continue;
    if (!usos.has(i.destino.id)) usos.set(i.destino.id, new Map());
    const m = usos.get(i.destino.id);
    for (const n of i.nombres) {
      if (!m.has(n)) m.set(n, new Set());
      m.get(n).add(f);
    }
  }
}

// ---------- roles por nombre de archivo ----------
function rolDe(f) {
  const b = path.basename(f);
  if (esTest(f)) return 'test';
  const reglas = [
    [/\.module\.(t|j)s$/, 'módulo'], [/\.controller\./, 'controlador'], [/\.resolver\./, 'controlador'],
    [/\.service\./, 'servicio'], [/\.repository\./, 'repositorio'],
    [/\.(dto|schema)\./, 'contrato'], [/\.(entity|model)\./, 'modelo'],
    [/\.(guard|strategy|interceptor|pipe|filter|middleware|decorator)\./, 'infra'],
    [/^(page)\.(t|j)sx?$/, 'página'], [/^(layout|template|loading|error|not-found)\.(t|j)sx?$/, 'layout'],
    [/^route\.(t|j)s$/, 'ruta API'], [/^middleware\.(t|j)s$/, 'infra'], [/^use[A-Z].*\.(t|j)sx?$/, 'hook'],
    [/\.(store|slice)\./, 'estado'], [/\.(types?|interfaces?)\.(t|j)s$/, 'tipos'], [/^index\.(t|j)sx?$/, 'barril'],
    [/\.(t|j)sx$/, 'componente'],
  ];
  for (const [re, rol] of reglas) if (re.test(b)) return rol;
  return 'código';
}
// archivos cuyos exports los usa el framework, no otros archivos
const NOMBRES_FRAMEWORK = new Set(['default', 'metadata', 'generateMetadata', 'generateStaticParams', 'generateViewport', 'viewport', 'revalidate', 'dynamic', 'dynamicParams', 'runtime', 'preferredRegion', 'maxDuration', 'fetchCache', 'config', 'middleware', 'GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS', 'register', 'onRequestError']);
function esEntradaFramework(f) {
  const b = path.basename(f);
  const r = relP(f);
  return /[\\/]app[\\/]/.test(r) && /^(page|layout|template|loading|error|not-found|global-error|default|route|opengraph-image|icon|sitemap|robots)\.(t|j)sx?$/.test(b)
    || /^(middleware|instrumentation|main)\.(t|j)s$/.test(b)
    || /[\\/]pages[\\/]/.test(r);
}

// ---------- declaraciones de cada archivo del bloque ----------
function declaraciones(sf) {
  const lista = [];
  const exportados = new Map(); // nodo de declaración -> nombre exportado
  const simMod = checker.getSymbolAtLocation(sf);
  if (simMod) {
    for (const s of checker.getExportsOfModule(simMod)) {
      let real = s;
      if (s.flags & ts.SymbolFlags.Alias) { try { real = checker.getAliasedSymbol(s); } catch { /* */ } }
      for (const d of real.declarations ?? []) if (d.getSourceFile() === sf) exportados.set(d, s.escapedName === 'default' ? 'default' : String(s.escapedName));
    }
  }
  const linea = (n) => sf.getLineAndCharacterOfPosition(n.getStart(sf)).line + 1;
  const agregar = (nodo, nombre, tipo) => lista.push({ nombre, tipo, linea: linea(nodo), exportadoComo: exportados.get(nodo) ?? null });
  const nombresBinding = (b) => ts.isIdentifier(b) ? [b] : b.elements.flatMap((e) => ts.isOmittedExpression(e) ? [] : nombresBinding(e.name));
  for (const st of sf.statements) {
    if (ts.isFunctionDeclaration(st)) agregar(st, st.name?.text ?? 'default', 'función');
    else if (ts.isClassDeclaration(st)) agregar(st, st.name?.text ?? 'default', 'clase');
    else if (ts.isInterfaceDeclaration(st)) agregar(st, st.name.text, 'interfaz');
    else if (ts.isTypeAliasDeclaration(st)) agregar(st, st.name.text, 'tipo');
    else if (ts.isEnumDeclaration(st)) agregar(st, st.name.text, 'enum');
    else if (ts.isVariableStatement(st)) {
      const tipo = st.declarationList.flags & ts.NodeFlags.Const ? 'const' : 'let';
      for (const d of st.declarationList.declarations) {
        for (const id of nombresBinding(d.name)) lista.push({ nombre: id.text, tipo, linea: linea(id), exportadoComo: exportados.get(d) ?? null });
      }
    } else if (ts.isExportAssignment(st)) {
      lista.push({ nombre: 'default', tipo: 'export default', linea: linea(st), exportadoComo: 'default' });
    }
  }
  return lista;
}

// ---------- armar nodos ----------
const rel = (f) => path.relative(proyectoDir, f).split(path.sep).join('/');
const nodos = new Map();
const aristas = [];
const lineasDe = (f) => { try { return fs.readFileSync(f, 'utf8').split('\n').length; } catch { return 0; } };

for (const f of archivosBloque) {
  const sf = sourceDe(f);
  const problemas = [];
  const diags = programa.getSemanticDiagnostics(sf);
  const sinUsoPorLinea = new Map();
  let erroresTs = 0;
  for (const d of diags) {
    if (d.start === undefined) continue;
    const linea = sf.getLineAndCharacterOfPosition(d.start).line + 1;
    const msg = ts.flattenDiagnosticMessageText(d.messageText, ' ');
    if (COD_SIN_USO.has(d.code)) {
      const nombre = (msg.match(/'([^']+)'/) ?? [])[1] ?? '?';
      problemas.push({ tipo: 'sin-usar', nombre, linea, detalle: traducir(d.code, nombre) });
      sinUsoPorLinea.set(`${linea}:${nombre}`, true);
    } else if (d.category === ts.DiagnosticCategory.Error) {
      erroresTs++;
      if (erroresTs <= 20) problemas.push({ tipo: 'error-ts', linea, detalle: `TS${d.code}: ${msg}` });
    }
  }
  const decls = declaraciones(sf).map((d) => {
    let estado = 'ok';
    let usadoPor = [];
    if (sinUsoPorLinea.has(`${d.linea}:${d.nombre}`)) estado = 'sin-usar';
    if (d.exportadoComo) {
      const m = usos.get(f);
      const directos = m?.get(d.exportadoComo) ?? new Set();
      const estrella = m?.get('*') ?? new Set();
      usadoPor = [...new Set([...directos, ...estrella])].filter((x) => x !== f);
      if (usadoPor.length === 0) {
        if (esEntradaFramework(f) && NOMBRES_FRAMEWORK.has(d.exportadoComo)) estado = 'framework';
        else estado = 'export-sin-usar';
      } else if (usadoPor.every(esTest) && !esTest(f)) estado = 'solo-tests';
    }
    return { ...d, estado, usadoPor: usadoPor.map(rel) };
  });
  const importadores = [...(usos.get(f)?.values() ?? [])].flatMap((s) => [...s]).filter((x) => x !== f);
  const huerfano = importadores.length === 0 && !esEntradaFramework(f) && !esTest(f);
  for (const d of decls) {
    if (d.estado === 'export-sin-usar' && !huerfano) problemas.push({ tipo: 'export-sin-usar', nombre: d.exportadoComo, linea: d.linea, detalle: `"${d.exportadoComo}" se exporta pero ningún archivo del proyecto lo importa` });
    if (d.estado === 'solo-tests') problemas.push({ tipo: 'solo-tests', nombre: d.exportadoComo, linea: d.linea, detalle: `"${d.exportadoComo}" solo lo usan los tests` });
  }
  if (huerfano) problemas.push({ tipo: 'huerfano', detalle: 'Ningún archivo del proyecto importa este archivo: todo lo que exporta está muerto' });
  nodos.set(f, {
    id: rel(f), etiqueta: path.basename(f), grupo: 'bloque', rol: rolDe(f), lineas: lineasDe(f),
    declaraciones: decls, problemas, erroresTs,
  });
}

function nodoExterno(destino, grupo) {
  if (nodos.has(destino.id)) return nodos.get(destino.id).id;
  const id = grupo === 'paquete' ? `pkg:${destino.id}` : grupo === 'roto' ? `roto:${destino.id}` : rel(destino.id);
  const etiqueta = grupo === 'paquete' ? destino.id : grupo === 'roto' ? destino.id : path.basename(destino.id);
  nodos.set(destino.id, { id, etiqueta, grupo, rol: grupo === 'proyecto' ? rolDe(destino.id) : grupo, ruta: grupo === 'proyecto' ? rel(destino.id) : null, declaraciones: [], problemas: grupo === 'roto' ? [{ tipo: 'roto', detalle: 'Este import no resuelve a ningún archivo' }] : [] });
  return id;
}

// aristas salientes del bloque
for (const f of archivosBloque) {
  const desde = nodos.get(f).id;
  for (const i of importsPorArchivo.get(f) ?? importsDe(sourceDe(f)).map((x) => ({ ...x, destino: resolver(x.spec, f) }))) {
    let a;
    if (i.destino.tipo === 'archivo') a = enBloque.has(i.destino.id) ? nodos.get(i.destino.id).id : nodoExterno(i.destino, 'proyecto');
    else a = nodoExterno(i.destino, i.destino.tipo === 'roto' ? 'roto' : 'paquete');
    if (a === desde) continue;
    const previa = aristas.find((x) => x.de === desde && x.a === a);
    if (previa) previa.nombres = [...new Set([...previa.nombres, ...i.nombres])];
    else aristas.push({ de: desde, a, nombres: i.nombres, forma: i.forma });
  }
}
// quién usa el bloque desde fuera
for (const [f, imps] of importsPorArchivo) {
  if (enBloque.has(f)) continue;
  for (const i of imps) {
    if (i.destino.tipo !== 'archivo' || !enBloque.has(i.destino.id)) continue;
    if (!nodos.has(f)) nodos.set(f, { id: rel(f), etiqueta: path.basename(f), grupo: 'consumidor', rol: rolDe(f), ruta: rel(f), declaraciones: [], problemas: [] });
    const de = nodos.get(f).id; const a = nodos.get(i.destino.id).id;
    const previa = aristas.find((x) => x.de === de && x.a === a);
    if (previa) previa.nombres = [...new Set([...previa.nombres, ...i.nombres])];
    else aristas.push({ de, a, nombres: i.nombres, forma: i.forma });
  }
}

// ---------- ciclos (Tarjan sobre archivos del bloque) ----------
const idsBloque = new Set([...nodos.values()].filter((n) => n.grupo === 'bloque').map((n) => n.id));
const ady = new Map([...idsBloque].map((id) => [id, []]));
for (const e of aristas) if (idsBloque.has(e.de) && idsBloque.has(e.a)) ady.get(e.de).push(e.a);
const ciclos = [];
{
  let idx = 0; const pila = []; const enPila = new Set(); const ind = new Map(); const low = new Map();
  const fuerte = (v) => {
    ind.set(v, idx); low.set(v, idx); idx++; pila.push(v); enPila.add(v);
    for (const w of ady.get(v)) {
      if (!ind.has(w)) { fuerte(w); low.set(v, Math.min(low.get(v), low.get(w))); }
      else if (enPila.has(w)) low.set(v, Math.min(low.get(v), ind.get(w)));
    }
    if (low.get(v) === ind.get(v)) {
      const comp = []; let w;
      do { w = pila.pop(); enPila.delete(w); comp.push(w); } while (w !== v);
      if (comp.length > 1) ciclos.push(comp);
    }
  };
  for (const v of idsBloque) if (!ind.has(v)) fuerte(v);
}
const enCiclo = new Map();
ciclos.forEach((c, i) => c.forEach((id) => enCiclo.set(id, i)));
for (const e of aristas) if (enCiclo.has(e.de) && enCiclo.get(e.de) === enCiclo.get(e.a)) e.ciclo = true;
for (const n of nodos.values()) if (enCiclo.has(n.id)) n.problemas.push({ tipo: 'ciclo', detalle: `Import circular con: ${ciclos[enCiclo.get(n.id)].filter((x) => x !== n.id).join(', ')}` });

// ---------- resumen y salida ----------
const listaNodos = [...nodos.values()];
const deBloque = listaNodos.filter((n) => n.grupo === 'bloque');
const contar = (t) => deBloque.reduce((s, n) => s + n.problemas.filter((p) => p.tipo === t).length, 0);
const nombre = args.nombre ?? path.basename(bloqueAbs);
const datos = {
  version: 1,
  bloque: nombre,
  carpeta: rel(bloqueAbs) || '.',
  proyecto: path.basename(proyectoDir),
  generado: new Date().toISOString(),
  motor: `TypeScript ${ts.version}`,
  resumen: {
    archivos: deBloque.length,
    lineas: deBloque.reduce((s, n) => s + n.lineas, 0),
    conexiones: aristas.filter((e) => idsBloque.has(e.de) || idsBloque.has(e.a)).length,
    sinUsar: contar('sin-usar'),
    exportsSinUsar: contar('export-sin-usar'),
    soloTests: contar('solo-tests'),
    huerfanos: contar('huerfano'),
    ciclos: ciclos.length,
    erroresTs: deBloque.reduce((s, n) => s + n.erroresTs, 0),
    paquetes: listaNodos.filter((n) => n.grupo === 'paquete').map((n) => n.etiqueta).sort(),
  },
  nodos: listaNodos,
  aristas,
};

function traducir(code, n) {
  switch (code) {
    case 6133: return `"${n}" se declara pero nunca se usa`;
    case 6138: return `La propiedad "${n}" se declara pero nunca se lee`;
    case 6192: return 'Ningún import de esta línea se usa';
    case 6196: return `"${n}" se declara pero nunca se usa`;
    case 6198: return 'Ninguna variable de esta desestructuración se usa';
    case 6199: return 'Ninguna variable de esta declaración se usa';
    case 6205: return 'Ningún parámetro de tipo se usa';
    default: return `"${n}" sin usar`;
  }
}

const salidaDir = path.resolve(args.salida ?? path.join(proyectoDir, 'docs', 'mapas'));
fs.mkdirSync(salidaDir, { recursive: true });
const base = nombre.replace(/[^\w.-]+/g, '-');
const json = JSON.stringify(datos, null, 2);
fs.writeFileSync(path.join(salidaDir, `${base}.json`), json);

const plantilla = fs.readFileSync(path.join(AQUI, 'plantilla.html'), 'utf8');
const seguro = JSON.stringify(datos).replace(/</g, '\\u003c').replace(/\u2028/g, '\\u2028').replace(/\u2029/g, '\\u2029');
fs.writeFileSync(path.join(salidaDir, `${base}.html`), plantilla.replace('__TITULO__', `Mapa: ${nombre.replace(/[<>&"]/g, '')}`).replace('"__DATOS__"', () => seguro));

fs.writeFileSync(path.join(salidaDir, `${base}.md`), markdown(datos));

const r = datos.resumen;
console.log(`Mapa del bloque "${nombre}" (${datos.motor})
  ${r.archivos} archivos, ${r.lineas} líneas, ${r.conexiones} conexiones
  ${r.sinUsar} sin usar · ${r.exportsSinUsar} exports sin usar · ${r.soloTests} solo en tests · ${r.huerfanos} huérfanos · ${r.ciclos} ciclos · ${r.erroresTs} errores TS
Archivos:
  ${path.join(salidaDir, `${base}.html`)}
  ${path.join(salidaDir, `${base}.json`)}
  ${path.join(salidaDir, `${base}.md`)}`);

// ---------- markdown con Mermaid ----------
function markdown(d) {
  const r = d.resumen;
  const ids = new Map();
  const mid = (id) => { if (!ids.has(id)) ids.set(id, `n${ids.size}`); return ids.get(id); };
  const esc = (s) => String(s).replace(/"/g, "'");
  const lineas = ['graph LR'];
  const consumidores = d.nodos.filter((n) => n.grupo === 'consumidor');
  const bloque = d.nodos.filter((n) => n.grupo === 'bloque');
  const fuera = d.nodos.filter((n) => n.grupo === 'proyecto' || n.grupo === 'roto');
  if (consumidores.length) {
    lineas.push('  subgraph usan["Lo usan"]');
    for (const n of consumidores) lineas.push(`    ${mid(n.id)}["${esc(n.etiqueta)}"]`);
    lineas.push('  end');
  }
  lineas.push(`  subgraph blq["Bloque ${esc(d.bloque)}"]`);
  for (const n of bloque) {
    const p = n.problemas.length;
    lineas.push(`    ${mid(n.id)}["${esc(n.etiqueta)}${p ? ` ⚠ ${p}` : ''}"]`);
  }
  lineas.push('  end');
  if (fuera.length) {
    lineas.push('  subgraph fue["Fuera del bloque"]');
    for (const n of fuera) lineas.push(`    ${mid(n.id)}["${esc(n.etiqueta)}"]`);
    lineas.push('  end');
  }
  for (const e of d.aristas) {
    const de = d.nodos.find((n) => n.id === e.de); const a = d.nodos.find((n) => n.id === e.a);
    if (!de || !a || a.grupo === 'paquete') continue;
    lineas.push(`  ${mid(e.de)} ${e.ciclo ? '-.->' : '-->'} ${mid(e.a)}`);
  }
  const conProblema = bloque.filter((n) => n.problemas.length).map((n) => mid(n.id));
  lineas.push('  classDef problema stroke:#c0392b,stroke-width:2px');
  if (conProblema.length) lineas.push(`  class ${conProblema.join(',')} problema`);

  const filas = bloque.flatMap((n) => n.problemas.map((p) => `| \`${n.id}\` | ${p.linea ?? ''} | ${p.tipo} | ${String(p.detalle).replace(/\|/g, '\\|')} |`));
  return `# Mapa del bloque ${d.bloque}

Generado ${d.generado.slice(0, 10)} con ${d.motor}. Carpeta: \`${d.carpeta}\`.

| Archivos | Líneas | Conexiones | Sin usar | Exports sin usar | Solo tests | Huérfanos | Ciclos | Errores TS |
|---|---|---|---|---|---|---|---|---|
| ${r.archivos} | ${r.lineas} | ${r.conexiones} | ${r.sinUsar} | ${r.exportsSinUsar} | ${r.soloTests} | ${r.huerfanos} | ${r.ciclos} | ${r.erroresTs} |

\`\`\`mermaid
${lineas.join('\n')}
\`\`\`

Paquetes: ${r.paquetes.length ? r.paquetes.map((p) => `\`${p}\``).join(', ') : 'ninguno'}

## Problemas

${filas.length ? `| Archivo | Línea | Tipo | Detalle |\n|---|---|---|---|\n${filas.join('\n')}` : 'Ninguno. Bloque limpio.'}
`;
}
