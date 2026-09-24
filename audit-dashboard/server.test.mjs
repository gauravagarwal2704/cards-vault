import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, before, test } from 'node:test';

import { createAuditServer } from './server.mjs';

let baseUrl;
let progressFile;
let server;
let temporaryDirectory;

before(async () => {
  temporaryDirectory = await mkdtemp(join(tmpdir(), 'cardvault-audit-server-'));
  progressFile = join(temporaryDirectory, 'task-progress.json');
  await writeFile(progressFile, JSON.stringify({ version: 1, updatedAt: '2026-08-27', tasks: { 'TEST-01': 'done' } }));
  server = createAuditServer({
    progressFile,
    allowedTaskIds: new Set(['TEST-01', 'TEST-02']),
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const address = server.address();
  baseUrl = `http://127.0.0.1:${address.port}`;
});

after(async () => {
  await new Promise((resolve) => server.close(resolve));
  await rm(temporaryDirectory, { recursive: true, force: true });
});

test('GET returns shared progress and PATCH persists an atomic update', async () => {
  const initial = await fetch(`${baseUrl}/api/tasks`).then((response) => response.json());
  assert.equal(initial.tasks['TEST-01'], 'done');

  const response = await fetch(`${baseUrl}/api/tasks/TEST-02`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ status: 'picked' }),
  });
  assert.equal(response.status, 200);
  const updated = await response.json();
  assert.equal(updated.tasks['TEST-02'], 'picked');

  const saved = JSON.parse(await readFile(progressFile, 'utf8'));
  assert.equal(saved.tasks['TEST-01'], 'done');
  assert.equal(saved.tasks['TEST-02'], 'picked');
});

test('skipped tasks persist and can be restored for future pickup', async () => {
  const skippedResponse = await fetch(`${baseUrl}/api/tasks/TEST-02`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ status: 'skipped' }),
  });
  assert.equal(skippedResponse.status, 200);
  assert.equal((await skippedResponse.json()).tasks['TEST-02'], 'skipped');

  const restoredResponse = await fetch(`${baseUrl}/api/tasks/TEST-02`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ status: 'backlog' }),
  });
  assert.equal(restoredResponse.status, 200);

  const saved = JSON.parse(await readFile(progressFile, 'utf8'));
  assert.equal(saved.tasks['TEST-02'], 'backlog');
});

test('PATCH rejects unknown tasks and invalid statuses', async () => {
  const unknown = await fetch(`${baseUrl}/api/tasks/UNKNOWN-01`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ status: 'done' }),
  });
  assert.equal(unknown.status, 404);

  const invalid = await fetch(`${baseUrl}/api/tasks/TEST-01`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ status: 'deleted' }),
  });
  assert.equal(invalid.status, 400);
});

test('cross-origin writes are limited to loopback dashboard origins', async () => {
  const response = await fetch(`${baseUrl}/api/tasks/TEST-01`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json', Origin: 'https://malicious.example' },
    body: JSON.stringify({ status: 'backlog' }),
  });
  assert.equal(response.status, 403);
});
