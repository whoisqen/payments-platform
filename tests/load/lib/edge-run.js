import http from 'k6/http';
import exec from 'k6/execution';
import { Trend, Rate } from 'k6/metrics';
import { assertStage } from './stage-guard.js';
import { HEADERS, EDGE_MIX, buildEdgeRequest, needsPaymentId } from './edge.js';
import { pickType } from './profiles.js';
import { isServerError } from './requests.js';

const overhead = new Trend('platform_overhead_ms', true);
const serverError = new Rate('server_error');
const shedRate = new Rate('shed_rate');
const retryAfter = new Rate('retry_after_present');
const okRate = new Rate('ok_rate');

// Runs at init, so a run against anything but stage stops before the first request.
export function loadConfig() {
  assertStage(__ENV);
  return {
    baseUrl: __ENV.BASE_URL,
    apiKey: __ENV.MERCHANT_API_KEY,
    paymentToken: __ENV.TEST_PAYMENT_TOKEN,
    idempotencyKey: () => `rl-${exec.vu.idInTest}-${exec.vu.iterationInScenario}`,
  };
}

// Per VU pool of payment ids by merchant; each VU is its own JS runtime.
const pools = {};
const POOL_MAX = 50;

function send(cfg, type, merchantId, paymentId, tags) {
  const r = buildEdgeRequest(type, cfg, merchantId, paymentId);
  const t = { ...tags, type, class: r.klass };
  const res = http.request(r.method, r.url, r.body, { headers: r.headers, tags: t });
  const pspMs = Number(res.headers['X-Psp-Latency-Ms'] || 0);
  overhead.add(Math.max(0, res.timings.duration - pspMs), t);
  serverError.add(isServerError(res.status), t);
  shedRate.add(res.status === 429, t);
  okRate.add(res.status >= 200 && res.status < 300, t);
  if (res.status === 429) retryAfter.add(res.headers[HEADERS.retryAfter] !== undefined, t);
  return res;
}

export function runOnce(cfg, merchantId, tags) {
  const type = pickType(Math.random(), EDGE_MIX);
  const pool = (pools[merchantId] = pools[merchantId] || []);
  let id = pool.length ? pool[Math.floor(Math.random() * pool.length)] : null;
  if (needsPaymentId(type) && !id) {
    const created = send(cfg, 'create', merchantId, null, { merchant_role: 'prime', phase: 'prime' });
    id = created.status === 200 ? created.json('payment_id') : null;
    if (!id) return;
    pool.push(id);
  }
  const res = send(cfg, type, merchantId, id, tags);
  if (type === 'create' && res.status === 200) {
    pool.push(res.json('payment_id'));
    if (pool.length > POOL_MAX) pool.shift();
  }
}
