import test from 'node:test';
import assert from 'node:assert/strict';
import { decide, validate, fromEnv, DEFAULTS } from '../mock-psp/psp-model.mjs';
import { createServer } from '../mock-psp/server.mjs';

test('defaults give 300-1500 ms latency and no faults', () => {
  const c = validate({});
  assert.deepEqual(c, DEFAULTS);
  assert.equal(decide(c, () => 0.5).delayMs, 900);
  assert.equal(decide(c, () => 0.99).kind, 'ok');
});

test('timeout and error rates are honoured by the roll', () => {
  const c = validate({ timeoutRate: 0.2, errorRate: 0.3 });
  assert.equal(decide(c, () => 0.1).kind, 'timeout');
  assert.equal(decide(c, () => 0.3).kind, 'error');
  assert.equal(decide(c, () => 0.9).kind, 'ok');
});

test('invalid configuration is rejected', () => {
  assert.throws(() => validate({ minMs: 10, maxMs: 5 }));
  assert.throws(() => validate({ errorRate: 0.7, timeoutRate: 0.5 }));
  assert.throws(() => fromEnv({ PSP_ERROR_RATE: '2' }));
});

async function withServer(cfg, fn) {
  const server = createServer(cfg);
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  try {
    await fn(`http://127.0.0.1:${server.address().port}`);
  } finally {
    server.closeAllConnections();
    await new Promise((r) => server.close(r));
  }
}

test('server answers with the latency header and counts outcomes', async () => {
  await withServer({ minMs: 1, maxMs: 3 }, async (base) => {
    const res = await fetch(`${base}/authorize`, { method: 'POST', body: '{}' });
    assert.equal(res.status, 200);
    assert.ok(Number(res.headers.get('x-psp-latency-ms')) >= 1);
    const stats = await (await fetch(`${base}/admin/stats`)).json();
    assert.equal(stats.ok, 1);
  });
});

test('runtime reconfiguration switches the PSP to errors, then to timeouts', async () => {
  await withServer({ minMs: 1, maxMs: 2 }, async (base) => {
    await fetch(`${base}/admin/config`, { method: 'POST', body: JSON.stringify({ errorRate: 1 }) });
    assert.equal((await fetch(`${base}/authorize`, { method: 'POST' })).status, 503);
    await fetch(`${base}/admin/config`, { method: 'POST', body: JSON.stringify({ errorRate: 0, timeoutRate: 1, timeoutMs: 20 }) });
    await assert.rejects(fetch(`${base}/authorize`, { method: 'POST' }));
    const bad = await fetch(`${base}/admin/config`, { method: 'POST', body: JSON.stringify({ errorRate: 5 }) });
    assert.equal(bad.status, 400);
  });
});
