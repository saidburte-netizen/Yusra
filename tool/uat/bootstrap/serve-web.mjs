#!/usr/bin/env node
// Tiny static server for the Flutter web build with SPA history fallback.
//
// GoRouter pushes paths such as /admin/users and /sales/:id. A plain
// `python -m http.server` returns 404 for those on a hard load, which would
// break the "direct URL shows Access denied" UAT checks. This server serves
// real files when present and falls back to index.html otherwise.
import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(process.env.UAT_WEB_ROOT ?? path.join(here, '..', '..', '..', 'build', 'web'));
const port = Number(process.env.UAT_WEB_PORT ?? '4173');

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.mjs': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.ico': 'image/x-icon',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.ttf': 'font/ttf',
  '.txt': 'text/plain; charset=utf-8',
};

async function resolveFile(urlPath) {
  const decoded = decodeURIComponent(urlPath.split('?')[0]);
  const candidate = path.resolve(root, `.${decoded}`);
  if (!candidate.startsWith(root)) return null;
  try {
    const info = await stat(candidate);
    if (info.isFile()) return candidate;
  } catch {
    // fall through to SPA fallback
  }
  return null;
}

createServer(async (req, res) => {
  const requested = req.url ?? '/';
  let file = await resolveFile(requested);
  let status = 200;
  if (!file) {
    file = path.join(root, 'index.html');
    status = 200; // SPA fallback: the router renders the 404/forbidden screen
  }
  try {
    const body = await readFile(file);
    res.writeHead(status, {
      'Content-Type': TYPES[path.extname(file).toLowerCase()] ?? 'application/octet-stream',
      'Cache-Control': 'no-store',
    });
    res.end(body);
  } catch (error) {
    res.writeHead(500, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end(`UAT web server error: ${error instanceof Error ? error.message : String(error)}`);
  }
}).listen(port, '127.0.0.1', () => {
  process.stdout.write(`UAT web server: http://127.0.0.1:${port} (root=${root})\n`);
});
