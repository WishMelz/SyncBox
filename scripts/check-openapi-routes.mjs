import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';

const ROOT = resolve(import.meta.dirname, '..');
const MODULES_DIR = join(ROOT, 'backend', 'src', 'modules');
const OPENAPI_PATH = join(ROOT, 'shared', 'contracts', 'openapi.yaml');

function collectControllerFiles(dir) {
  const files = [];
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) {
      files.push(...collectControllerFiles(full));
    } else if (entry.endsWith('.controller.ts')) {
      files.push(full);
    }
  }
  return files;
}

function normalizePath(prefix, sub) {
  const joined = [prefix, sub]
    .map((part) => part.replace(/^\/+|\/+$/g, ''))
    .filter(Boolean)
    .join('/');
  return (
    '/' +
    joined
      .split('/')
      .map((seg) => (seg.startsWith(':') ? `{${seg.slice(1)}}` : seg))
      .join('/')
  );
}

function extractControllerRoutes() {
  const routes = new Set();
  const files = collectControllerFiles(MODULES_DIR);
  for (const file of files) {
    const source = readFileSync(file, 'utf8');
    const controllerMatch = /@Controller\(\s*['"`]([^'"`]*)['"`]\s*\)/.exec(source);
    if (!controllerMatch) {
      throw new Error(`Could not locate @Controller(...) in ${file}`);
    }
    const base = controllerMatch[1];
    const methodPattern = /@(Get|Post|Patch|Put|Delete)\(\s*(?:['"`]([^'"`]*)['"`])?\s*\)/g;
    let match;
    while ((match = methodPattern.exec(source)) !== null) {
      const method = match[1].toUpperCase();
      const sub = match[2] ?? '';
      routes.add(`${method} ${normalizePath(base, sub)}`);
    }
  }
  return routes;
}

function extractOpenApiRoutes() {
  const raw = readFileSync(OPENAPI_PATH, 'utf8');
  const spec = JSON.parse(raw);
  const routes = new Set();
  const httpMethods = new Set(['get', 'post', 'patch', 'put', 'delete', 'options', 'head']);
  for (const [path, operations] of Object.entries(spec.paths ?? {})) {
    for (const method of Object.keys(operations ?? {})) {
      if (httpMethods.has(method.toLowerCase())) {
        routes.add(`${method.toUpperCase()} ${path}`);
      }
    }
  }
  return routes;
}

const controllerRoutes = extractControllerRoutes();
const openApiRoutes = extractOpenApiRoutes();

const missingInOpenApi = [...controllerRoutes].filter((r) => !openApiRoutes.has(r)).sort();
const extraInOpenApi = [...openApiRoutes].filter((r) => !controllerRoutes.has(r)).sort();

if (missingInOpenApi.length || extraInOpenApi.length) {
  if (missingInOpenApi.length) {
    console.error('Routes implemented in controllers but missing from shared/contracts/openapi.yaml:');
    for (const r of missingInOpenApi) console.error(`  - ${r}`);
  }
  if (extraInOpenApi.length) {
    console.error('Routes in shared/contracts/openapi.yaml not found in controllers:');
    for (const r of extraInOpenApi) console.error(`  - ${r}`);
  }
  process.exit(1);
}

console.log(`OpenAPI parity OK (${controllerRoutes.size} routes verified).`);
