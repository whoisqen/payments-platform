import exec from 'k6/execution';
import { stagesToK6, preAllocatedVUs } from '../load/lib/profiles.js';
import { hotShare, sharePhase, pickMerchant } from '../load/lib/traffic.js';
import { loadConfig, runOnce } from '../load/lib/edge-run.js';

// One tenant goes from 5% to 60% of the traffic in 60 s (section 21); TOTAL_RPS must put 60% above the stage tenant limit.
const TOTAL_RPS = Number(__ENV.TOTAL_RPS || 1000);
const SHARE = { base: 0.05, peak: 0.6, rampStart: 60, rampSec: 60 };
const HOT = __ENV.HOT_MERCHANT_ID;
const OTHERS = (__ENV.OTHER_MERCHANT_IDS || '').split(',').filter(Boolean);
const profile = { stages: [{ sec: 30, to: TOTAL_RPS }, { sec: 270, to: TOTAL_RPS }, { sec: 30, to: 0 }] };
const pre = preAllocatedVUs(TOTAL_RPS);
const cfg = loadConfig();
if (!HOT || OTHERS.length === 0) throw new Error('HOT_MERCHANT_ID and OTHER_MERCHANT_IDS are required');

export const options = {
  scenarios: {
    hot_merchant: {
      executor: 'ramping-arrival-rate',
      startRate: 0,
      timeUnit: '1s',
      preAllocatedVUs: pre,
      maxVUs: pre * 2,
      stages: stagesToK6(profile),
    },
  },
  thresholds: {
    // Other merchants: success rate, latency and 5xx as without the hot tenant; their payments are never shed.
    'ok_rate{merchant_role:other}': ['rate>0.999'],
    'server_error{merchant_role:other}': ['rate<0.0001'],
    'platform_overhead_ms{merchant_role:other}': ['p(99)<150'],
    'http_req_duration{merchant_role:other,type:status}': ['p(99)<50'],
    'shed_rate{merchant_role:other,class:payments}': ['rate==0'],
    // Hot merchant: limited with 429 and Retry-After, never 5xx; its lists are shed as well.
    'shed_rate{merchant_role:hot,phase:hot}': ['rate>0'],
    'shed_rate{merchant_role:hot,class:list}': ['rate>0'],
    'server_error{merchant_role:hot}': ['rate==0'],
    'retry_after_present{merchant_role:hot}': ['rate==1'],
  },
};

export default function () {
  const elapsed = (Date.now() - exec.scenario.startTime) / 1000;
  const share = hotShare(elapsed, SHARE);
  const m = pickMerchant(Math.random(), share, HOT, OTHERS);
  runOnce(cfg, m.id, { merchant_role: m.role, phase: sharePhase(share, SHARE) });
}
