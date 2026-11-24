import test from 'node:test';
import assert from 'node:assert/strict';
import { classifyRequest, buildEdgeRequest, EDGE_MIX, HEADERS } from '../lib/edge.js';
import { guardReasons, assertStage } from '../lib/stage-guard.js';
import { hotShare, sharePhase, pickMerchant, loadPhase, shedProfile } from '../lib/traffic.js';
import { weightTotal } from '../lib/profiles.js';

const cfg = { baseUrl: 'https://stage.example', apiKey: 'k', paymentToken: 't', idempotencyKey: () => 'i' };

test('class is derived from the path of every built request', () => {
  const expected = { create: 'payments', confirm: 'payments', refund: 'payments', webhook: 'payments', status: 'read', methods: 'read', list: 'list', report: 'list' };
  for (const [type, klass] of Object.entries(expected)) {
    const r = buildEdgeRequest(type, cfg, 'm1', 'pay_1');
    assert.equal(r.klass, klass, type);
    assert.equal(r.headers[HEADERS.merchant], 'm1');
  }
  assert.equal(classifyRequest('GET', '/payments/list?limit=1'), 'list');
});

test('payments weights keep the 7-call table, lists add about 10%', () => {
  const paymentCalls = EDGE_MIX.filter((m) => !['list', 'report'].includes(m.type));
  assert.equal(weightTotal(paymentCalls), 7);
  assert.ok(Math.abs(0.8 / weightTotal(EDGE_MIX) - 0.1) < 0.01);
});

test('stage guard refuses other environments, freeze, incident, prod host', () => {
  const ok = { TARGET_ENV: 'stage', BASE_URL: 'https://api.stage.example' };
  assert.deepEqual(guardReasons(ok), []);
  for (const bad of [{ TARGET_ENV: 'prod' }, { TARGET_ENV: 'dev' }, { TARGET_ENV: undefined }, { FREEZE: 'true' }, { OPEN_INCIDENTS: '1' }, { BASE_URL: 'https://api.prod.example' }, { BASE_URL: '' }]) {
    assert.throws(() => assertStage({ ...ok, ...bad }), /refusing to run/, JSON.stringify(bad));
  }
});

test('hot share ramps from 5% to 60% in 60 s and merchants are picked by it', () => {
  const p = { base: 0.05, peak: 0.6, rampStart: 60, rampSec: 60 };
  assert.equal(hotShare(0, p), 0.05);
  assert.ok(Math.abs(hotShare(90, p) - 0.325) < 1e-9);
  assert.equal(hotShare(500, p), 0.6);
  assert.deepEqual([sharePhase(0.05, p), sharePhase(0.3, p), sharePhase(0.6, p)], ['baseline', 'ramp', 'hot']);
  let hot = 0;
  for (let i = 0; i < 1000; i++) if (pickMerchant(i / 1000, 0.6, 'h', ['a', 'b']).role === 'hot') hot++;
  assert.equal(hot, 600);
  assert.equal(pickMerchant(0.999, 0.6, 'h', ['a', 'b']).id, 'b');
});

test('shedding phases follow capacity', () => {
  assert.deepEqual([loadPhase(2000, 2000), loadPhase(2500, 2000), loadPhase(5000, 2000)], ['within', 'over', 'heavy']);
  assert.equal(Math.max(...shedProfile(2000).stages.map((s) => s.to)), 5000);
});
