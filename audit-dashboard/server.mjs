import { spawn } from 'node:child_process';
import { readFile, rename, unlink, writeFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const dashboardRoot = dirname(fileURLToPath(import.meta.url));
const defaultProgressFile = resolve(dashboardRoot, 'data/task-progress.json');
const auditDataFile = resolve(dashboardRoot, 'app/audit-data.ts');
const validStatuses = new Set(['backlog', 'picked', 'in-progress', 'blocked', 'done', 'skipped']);

function sendJson(response, statusCode, payload, origin) {
  const body = JSON.stringify(payload);
  response.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
    'Cache-Control': 'no-store',
    ...(origin ? { 'Access-Control-Allow-Origin': origin, Vary: 'Origin' } : {}),
  });
  response.end(body);
}

function isAllowedOrigin(origin, configuredOrigins) {
  if (!origin) return true;
  if (configuredOrigins.has(origin)) return true;
  try {
    const url = new URL(origin);
    return url.protocol === 'http:' && (url.hostname === 'localhost' || url.hostname === '127.0.0.1');
  } catch {
    return false;
  }
}

async function parseBody(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > 4096) {
      const error = new Error('Request body is too large.');
      error.statusCode = 413;
      throw error;
    }
    chunks.push(chunk);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch {
    const error = new Error('Request body must be valid JSON.');
    error.statusCode = 400;
    throw error;
  }
}

async function loadTaskIds() {
  const source = await readFile(auditDataFile, 'utf8');
  return new Set(Array.from(source.matchAll(/\btask\(\s*['"]([A-Z]+-\d+)['"]/g), (match) => match[1]));
}

function normalizeProgress(value, allowedTaskIds) {
  const tasks = {};
  if (value && typeof value === 'object' && value.tasks && typeof value.tasks === 'object') {
    for (const [id, status] of Object.entries(value.tasks)) {
      if (allowedTaskIds.has(id) && validStatuses.has(status)) tasks[id] = status;
    }
  }
  return {
    version: 1,
    updatedAt: typeof value?.updatedAt === 'string' ? value.updatedAt : new Date().toISOString(),
    tasks: Object.fromEntries(Object.entries(tasks).sort(([left], [right]) => left.localeCompare(right))),
  };
}

async function readProgress(progressFile, allowedTaskIds) {
  const contents = await readFile(progressFile, 'utf8');
  return normalizeProgress(JSON.parse(contents), allowedTaskIds);
}

async function writeProgress(progressFile, progress) {
  const temporaryFile = `${progressFile}.${process.pid}.${Date.now()}.tmp`;
  try {
    await writeFile(temporaryFile, `${JSON.stringify(progress, null, 2)}\n`, { encoding: 'utf8', mode: 0o600 });
    await rename(temporaryFile, progressFile);
  } catch (error) {
    await unlink(temporaryFile).catch(() => {});
    throw error;
  }
}

export function createAuditServer({
  progressFile = defaultProgressFile,
  allowedTaskIds,
  allowedOrigins = new Set(),
} = {}) {
  let writeQueue = Promise.resolve();

  return createServer(async (request, response) => {
    const origin = request.headers.origin;
    if (!isAllowedOrigin(origin, allowedOrigins)) {
      sendJson(response, 403, { error: 'Origin is not allowed.' });
      return;
    }

    if (request.method === 'OPTIONS') {
      response.writeHead(204, {
        ...(origin ? { 'Access-Control-Allow-Origin': origin, Vary: 'Origin' } : {}),
        'Access-Control-Allow-Methods': 'GET, PATCH, DELETE, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type',
        'Access-Control-Max-Age': '600',
      });
      response.end();
      return;
    }

    try {
      const taskIds = allowedTaskIds ?? await loadTaskIds();
      const url = new URL(request.url ?? '/', 'http://localhost');

      if (request.method === 'GET' && url.pathname === '/health') {
        sendJson(response, 200, { ok: true }, origin);
        return;
      }

      if (request.method === 'GET' && url.pathname === '/api/tasks') {
        sendJson(response, 200, await readProgress(progressFile, taskIds), origin);
        return;
      }

      if (request.method === 'DELETE' && url.pathname === '/api/tasks') {
        const result = await (writeQueue = writeQueue.then(async () => {
          const progress = { version: 1, updatedAt: new Date().toISOString(), tasks: {} };
          await writeProgress(progressFile, progress);
          return progress;
        }));
        sendJson(response, 200, result, origin);
        return;
      }

      const taskMatch = url.pathname.match(/^\/api\/tasks\/([^/]+)$/);
      if (request.method === 'PATCH' && taskMatch) {
        const id = decodeURIComponent(taskMatch[1]);
        if (!taskIds.has(id)) {
          sendJson(response, 404, { error: 'Unknown Task ID.' }, origin);
          return;
        }
        const body = await parseBody(request);
        if (!body || !validStatuses.has(body.status)) {
          sendJson(response, 400, { error: 'Invalid task status.' }, origin);
          return;
        }

        const result = await (writeQueue = writeQueue.then(async () => {
          const current = await readProgress(progressFile, taskIds);
          const progress = normalizeProgress({
            ...current,
            updatedAt: new Date().toISOString(),
            tasks: { ...current.tasks, [id]: body.status },
          }, taskIds);
          await writeProgress(progressFile, progress);
          return progress;
        }));
        sendJson(response, 200, result, origin);
        return;
      }

      sendJson(response, 404, { error: 'Not found.' }, origin);
    } catch (error) {
      const statusCode = Number.isInteger(error?.statusCode) ? error.statusCode : 500;
      sendJson(response, statusCode, { error: statusCode === 500 ? 'Unable to update task progress.' : error.message }, origin);
      if (statusCode === 500) console.error(error);
    }
  });
}

async function run() {
  const port = Number.parseInt(process.env.AUDIT_API_PORT ?? '3001', 10);
  const host = process.env.AUDIT_API_HOST ?? '127.0.0.1';
  const configuredOrigins = new Set((process.env.AUDIT_ALLOWED_ORIGINS ?? '').split(',').map((value) => value.trim()).filter(Boolean));
  const server = createAuditServer({ allowedOrigins: configuredOrigins });
  const apiOnly = process.argv.includes('--api-only');
  let client;

  server.listen(port, host, () => {
    console.log(`Audit status server: http://${host}:${port}`);
    if (!apiOnly) {
      client = spawn('npm', ['run', 'dev:web'], {
        cwd: dashboardRoot,
        env: { ...process.env, NEXT_PUBLIC_AUDIT_API_URL: process.env.NEXT_PUBLIC_AUDIT_API_URL ?? `http://localhost:${port}` },
        stdio: 'inherit',
        shell: process.platform === 'win32',
      });
      client.on('exit', (code) => {
        if (code && code !== 0) process.exitCode = code;
        server.close();
      });
    }
  });

  function shutdown() {
    if (client && !client.killed) client.kill('SIGTERM');
    server.close(() => process.exit());
  }
  process.once('SIGINT', shutdown);
  process.once('SIGTERM', shutdown);
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  run().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}
