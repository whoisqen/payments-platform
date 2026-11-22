import http from 'node:http';
import { randomUUID } from 'node:crypto';
import { decide, fromEnv, validate } from './psp-model.mjs';

export function createServer(initial = fromEnv(process.env)) {
  let cfg = validate(initial);
  const stats = { ok: 0, error: 0, timeout: 0 };

  const server = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://mock');
    if (url.pathname === '/admin/stats') return json(res, 200, { ...stats, config: cfg });
    if (url.pathname === '/admin/config' && req.method === 'POST') return readBody(req, (body) => reconfigure(res, body));
    if (!['/authorize', '/refund', '/status'].includes(url.pathname)) return json(res, 404, { error: 'not_found' });
    req.resume();
    const d = decide(cfg);
    stats[d.kind] += 1;
    const timer = setTimeout(() => {
      if (d.kind === 'timeout') return res.socket.destroy();
      res.setHeader('X-Psp-Latency-Ms', String(d.delayMs));
      if (d.kind === 'error') return json(res, d.status, { error: 'psp_unavailable' });
      json(res, 200, { psp_reference: randomUUID(), status: 'succeeded' });
    }, d.delayMs);
    timer.unref();
    res.on('close', () => clearTimeout(timer));
  });

  function reconfigure(res, body) {
    try {
      cfg = validate({ ...cfg, ...JSON.parse(body) });
      json(res, 200, cfg);
    } catch (e) {
      json(res, 400, { error: e.message });
    }
  }
  return server;
}

function json(res, status, obj) {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(obj));
}

function readBody(req, done) {
  let data = '';
  req.on('data', (c) => (data += c));
  req.on('end', () => done(data));
}

if (import.meta.url === `file://${process.argv[1]}`) {
  createServer().listen(Number(process.env.PORT || 8089), () => console.error('mock psp listening'));
}
