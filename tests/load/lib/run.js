import http from 'k6/http';
import exec from 'k6/execution';
import crypto from 'k6/crypto';
import { Trend, Rate, Counter } from 'k6/metrics';
import { MIX, PROFILES, SLO_RPS_LIMIT, pickType, targetRateAt } from './profiles.js';
import { buildRequest, needsPayment, isServerError } from './requests.js';

const overhead = new Trend('platform_overhead_ms', true);
const serverError = new Rate('server_error');
const shed = new Counter('shed_429');

const cfg = {
  baseUrl: __ENV.BASE_URL,
  apiKey: __ENV.MERCHANT_API_KEY,
  merchantId: __ENV.MERCHANT_ID,
  paymentToken: __ENV.TEST_PAYMENT_TOKEN,
  idempotencyKey: () => `lt-${exec.vu.idInTest}-${exec.vu.iterationInScenario}`,
};
const sign = (body) => crypto.hmac('sha256', __ENV.WEBHOOK_SECRET || '', body, 'hex');

// Each VU is its own JS runtime, so this pool is per VU and needs no locking.
const pool = [];
const POOL_MAX = 50;

function call(type, paymentId, tags) {
  const r = buildRequest(type, cfg, paymentId, sign);
  const res = http.request(r.method, r.url, r.body, { headers: r.headers, tags: { ...tags, type } });
  // Assumes the dummy connector reports its own latency in this header; without it all time counts as overhead.
  const pspMs = Number(res.headers['X-Psp-Latency-Ms'] || 0);
  overhead.add(Math.max(0, res.timings.duration - pspMs), { ...tags, type });
  serverError.add(isServerError(res.status), { ...tags, type });
  if (res.status === 429) shed.add(1, { ...tags, type });
  return res;
}

export function makeIteration(profileName) {
  const profile = PROFILES[profileName];
  return function iteration() {
    const elapsed = (Date.now() - exec.scenario.startTime) / 1000;
    const phase = targetRateAt(profile, elapsed) <= SLO_RPS_LIMIT ? 'within-slo' : 'beyond-slo';
    const type = pickType(Math.random(), MIX);
    let id = pool.length ? pool[Math.floor(Math.random() * pool.length)] : null;
    // A dependent call with an empty pool first creates a payment, tagged apart so the weights stay clean.
    if (needsPayment(type) && !id) {
      const created = call('create', null, { phase, role: 'prime' });
      id = created.status === 200 ? created.json('payment_id') : null;
      if (!id) return;
      pool.push(id);
    }
    const res = call(type, id, { phase, role: 'mix' });
    if (type === 'create' && res.status === 200) {
      pool.push(res.json('payment_id'));
      if (pool.length > POOL_MAX) pool.shift();
    }
  };
}
