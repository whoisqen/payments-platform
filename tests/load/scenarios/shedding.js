import exec from 'k6/execution';
import { stagesToK6, peakRps, preAllocatedVUs, targetRateAt } from '../lib/profiles.js';
import { shedProfile, loadPhase } from '../lib/traffic.js';
import { loadConfig, runOnce } from '../lib/edge-run.js';

// 2000 RPS is the capacity of one gateway pod (rateLimit in the payments-edge chart); PODS scales it.
const CAPACITY = 2000 * Number(__ENV.PODS || 1);
const profile = shedProfile(CAPACITY);
const pre = preAllocatedVUs(peakRps(profile));
const cfg = loadConfig();

// Order of shedding: lists and reports first, reads next, payments last; 5xx stays below 0.1% at any load.
export const options = {
  scenarios: {
    shedding: {
      executor: 'ramping-arrival-rate',
      startRate: 0,
      timeUnit: '1s',
      preAllocatedVUs: pre,
      maxVUs: pre * 2,
      stages: stagesToK6(profile),
    },
  },
  thresholds: {
    server_error: ['rate<0.001'],
    'shed_rate{phase:within}': ['rate<0.001'],
    'shed_rate{phase:over,class:list}': ['rate>0'],
    'shed_rate{phase:over,class:read}': ['rate<0.001'],
    'shed_rate{phase:over,class:payments}': ['rate<0.001'],
    'shed_rate{phase:heavy,class:list}': ['rate>0'],
    'shed_rate{phase:heavy,class:read}': ['rate>0'],
    'shed_rate{phase:heavy,class:payments}': ['rate<0.001'],
    retry_after_present: ['rate==1'],
  },
};

export default function () {
  const elapsed = (Date.now() - exec.scenario.startTime) / 1000;
  const phase = loadPhase(targetRateAt(profile, elapsed), CAPACITY);
  runOnce(cfg, __ENV.MERCHANT_ID, { merchant_role: 'other', phase });
}
