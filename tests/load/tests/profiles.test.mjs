import test from 'node:test';
import assert from 'node:assert/strict';
import { MIX, PROFILES, CALLS_PER_PAYMENT, weightTotal, pickType, targetRateAt, peakRps, totalSeconds, phaseAt } from '../lib/profiles.js';
import { buildOptions, thresholdsFor } from '../lib/options.js';
import { buildRequest, isServerError } from '../lib/requests.js';

test('mix weights sum to 7 calls per payment with status read twice', () => {
  assert.equal(weightTotal(), CALLS_PER_PAYMENT);
  assert.equal(MIX.find((m) => m.type === 'status').weight, 2);
});

test('pickType follows the weights over a uniform sweep', () => {
  const n = 7000;
  const counts = {};
  for (let i = 0; i < n; i++) {
    const t = pickType((i + 0.5) / n);
    counts[t] = (counts[t] || 0) + 1;
  }
  assert.equal(counts.status, 2000);
  for (const t of ['create', 'confirm', 'methods', 'webhook', 'refund']) assert.equal(counts[t], 1000);
});

test('profile RPS is TPS x 7 within 2% and peaks match the stages', () => {
  for (const [name, p] of Object.entries(PROFILES)) {
    if (name === 'smoke') continue;
    assert.ok(Math.abs(p.rps - p.tps * CALLS_PER_PAYMENT) / p.rps < 0.02, name);
    assert.equal(peakRps(p), p.rps, name);
  }
  assert.deepEqual([160, 480, 1430, 2860], ['average', 'daily-peak', 'sale-peak', 'stress'].map((n) => PROFILES[n].tps));
});

test('targetRateAt interpolates and ends at the last target', () => {
  const p = PROFILES['sale-peak'];
  assert.equal(targetRateAt(p, 0), 0);
  assert.equal(targetRateAt(p, 60), 3300);
  assert.equal(targetRateAt(p, 90), 6650);
  assert.equal(targetRateAt(p, 500), 10000);
  assert.equal(targetRateAt(p, totalSeconds(p) + 5), 0);
});

test('every profile uses an open-model executor', () => {
  for (const name of Object.keys(PROFILES)) {
    const o = buildOptions(name);
    assert.equal(o.scenarios[name].executor, 'ramping-arrival-rate');
    assert.ok(o.scenarios[name].maxVUs >= o.scenarios[name].preAllocatedVUs);
  }
});

test('SLO thresholds match section 1', () => {
  const t = thresholdsFor('sale-peak');
  assert.deepEqual(t.platform_overhead_ms, ['p(99)<150']);
  assert.deepEqual(t['http_req_duration{type:status}'], ['p(99)<50']);
  assert.deepEqual(t['server_error{type:confirm}'], ['rate<0.0001']);
});

test('breakpoint aborts on fail; stress splits SLO and degradation phases', () => {
  for (const list of Object.values(thresholdsFor('breakpoint'))) assert.equal(list[0].abortOnFail, true);
  const s = thresholdsFor('stress');
  assert.ok('server_error{phase:beyond-slo}' in s);
  assert.ok('platform_overhead_ms{phase:within-slo}' in s);
});

test('requests: confirm targets the payment and no card number is built in', () => {
  const cfg = { baseUrl: 'http://x', apiKey: 'k', merchantId: 'm', paymentToken: 'tok', idempotencyKey: () => 'i' };
  const r = buildRequest('confirm', cfg, 'pay_1');
  assert.equal(r.url, 'http://x/payments/pay_1/confirm');
  assert.ok(!/card_number/.test(r.body));
  assert.equal(buildRequest('status', cfg, 'pay_1').method, 'GET');
  assert.throws(() => buildRequest('nope', cfg, 'p'));
  assert.ok(isServerError(503) && !isServerError(429));
});

test('spike jumps from 3,300 to 10,000 RPS in 60 s and holds 15 min', () => {
  const p = PROFILES.spike;
  assert.equal(targetRateAt(p, 120), 3300);
  assert.equal(targetRateAt(p, 180), 10000);
  assert.equal(targetRateAt(p, 180 + 900), 10000);
  assert.equal(peakRps(p), 10000);
});

test('spike has its own 2 min start phase; stress still splits at 10,000 RPS', () => {
  const p = PROFILES.spike;
  assert.equal(phaseAt(p, 60), 'within-slo');
  assert.equal(phaseAt(p, 150), 'spike-start');
  assert.equal(phaseAt(p, 239), 'spike-start');
  assert.equal(phaseAt(p, 300), 'within-slo');
  assert.equal(phaseAt(PROFILES.stress, 1700), 'beyond-slo');
  assert.equal(phaseAt(PROFILES.stress, 600), 'within-slo');
  const t = thresholdsFor('spike');
  assert.deepEqual(t['server_error{phase:spike-start}'], ['rate<0.001']);
});

test('soak holds 2,500 RPS for 8 hours', () => {
  const p = PROFILES.soak;
  assert.equal(targetRateAt(p, 300 + 3600), 2500);
  assert.equal(totalSeconds(p), 300 + 8 * 3600 + 60);
});
