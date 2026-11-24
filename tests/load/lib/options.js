import { PROFILES, stagesToK6, peakRps, preAllocatedVUs } from './profiles.js';

function abortOnFail(expr) {
  return { threshold: expr, abortOnFail: true, delayAbortEval: '30s' };
}

// Section 1 SLOs: overhead p99 < 150 ms, status p99 < 50 ms, 5xx on confirm < 0.01%.
export function thresholdsFor(name) {
  const slo = {
    platform_overhead_ms: ['p(99)<150'],
    'http_req_duration{type:status}': ['p(99)<50'],
    'server_error{type:confirm}': ['rate<0.0001'],
    server_error: ['rate<0.0001'],
  };
  if (name === 'breakpoint') {
    return {
      platform_overhead_ms: [abortOnFail('p(99)<150')],
      server_error: [abortOnFail('rate<0.001')],
    };
  }
  if (name === 'stress') {
    // Tags from run.js split the ramp at 10,000 RPS: SLOs below it, only 5xx control above it.
    return {
      'platform_overhead_ms{phase:within-slo}': slo.platform_overhead_ms,
      'http_req_duration{type:status,phase:within-slo}': slo['http_req_duration{type:status}'],
      'server_error{type:confirm,phase:within-slo}': slo['server_error{type:confirm}'],
      'server_error{phase:beyond-slo}': ['rate<0.001'],
    };
  }
  if (name === 'spike') {
    // The first 2 min of the jump only need 5xx below 0.1%; the SLOs apply before it and after it.
    return {
      'platform_overhead_ms{phase:within-slo}': slo.platform_overhead_ms,
      'http_req_duration{type:status,phase:within-slo}': slo['http_req_duration{type:status}'],
      'server_error{type:confirm,phase:within-slo}': slo['server_error{type:confirm}'],
      'server_error{phase:spike-start}': ['rate<0.001'],
    };
  }
  return slo;
}

export function buildOptions(name) {
  const profile = PROFILES[name];
  if (!profile) throw new Error(`unknown profile ${name}`);
  const pre = preAllocatedVUs(peakRps(profile));
  return {
    scenarios: {
      [name]: {
        executor: 'ramping-arrival-rate',
        startRate: 0,
        timeUnit: '1s',
        preAllocatedVUs: pre,
        maxVUs: pre * 2,
        stages: stagesToK6(profile),
      },
    },
    thresholds: thresholdsFor(name),
  };
}
