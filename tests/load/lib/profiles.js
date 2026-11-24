// Load model of section 1: 1 TPS is about 7 router calls; the rounded RPS values are the ones the document states.
export const CALLS_PER_PAYMENT = 7;

export const MIX = [
  { type: 'create', weight: 1 },
  { type: 'confirm', weight: 1 },
  { type: 'status', weight: 2 },
  { type: 'methods', weight: 1 },
  { type: 'webhook', weight: 1 },
  { type: 'refund', weight: 1 },
];

// Above this RPS the SLOs are not asserted, only controlled degradation (429, not 5xx).
export const SLO_RPS_LIMIT = 10000;

// Average time in flight per call: confirm and refund wait for the PSP (about 0.8 s), the rest is below 50 ms.
export const AVG_INFLIGHT_SEC = 0.27;

export const PROFILES = {
  smoke: { tps: 1, rps: 5, stages: [{ sec: 10, to: 5 }, { sec: 50, to: 5 }] },
  average: { tps: 160, rps: 1100, stages: [{ sec: 300, to: 1100 }, { sec: 1800, to: 1100 }, { sec: 60, to: 0 }] },
  'daily-peak': { tps: 480, rps: 3300, stages: [{ sec: 300, to: 3300 }, { sec: 1800, to: 3300 }, { sec: 60, to: 0 }] },
  'sale-peak': { tps: 1430, rps: 10000, stages: [{ sec: 60, to: 3300 }, { sec: 60, to: 10000 }, { sec: 900, to: 10000 }, { sec: 60, to: 0 }] },
  stress: { tps: 2860, rps: 20000, stages: [{ sec: 1800, to: 20000 }, { sec: 60, to: 0 }] },
  // Section 8: 3,300 -> 10,000 RPS in 60 s, held 15 min; only 5xx below 0.1% in the first 2 min of the spike, the SLOs after that.
  spike: {
    tps: 1430,
    rps: 10000,
    stages: [{ sec: 60, to: 3300 }, { sec: 60, to: 3300 }, { sec: 60, to: 10000 }, { sec: 900, to: 10000 }, { sec: 60, to: 0 }],
    phases: [{ until: 120, name: 'within-slo' }, { until: 240, name: 'spike-start' }],
  },
  // Section 8: 2,500 RPS for 8 h; the checks of memory (pods, MemoryDB) come from the monitoring, not from k6.
  soak: { tps: 357, rps: 2500, stages: [{ sec: 300, to: 2500 }, { sec: 28800, to: 2500 }, { sec: 60, to: 0 }] },
  breakpoint: { tps: 2860, rps: 20000, stages: [{ sec: 1800, to: 20000 }] },
};

export function weightTotal(mix = MIX) {
  return mix.reduce((sum, m) => sum + m.weight, 0);
}

// r in [0, 1) picks a request type proportionally to its weight.
export function pickType(r, mix = MIX) {
  let acc = r * weightTotal(mix);
  for (const m of mix) {
    if (acc < m.weight) return m.type;
    acc -= m.weight;
  }
  return mix[mix.length - 1].type;
}

export function stagesToK6(profile) {
  return profile.stages.map((s) => ({ duration: `${s.sec}s`, target: s.to }));
}

export function peakRps(profile) {
  return Math.max(...profile.stages.map((s) => s.to));
}

// Linear interpolation of the arrival rate planned at a given second of the run.
export function targetRateAt(profile, elapsedSec) {
  let from = 0;
  let t = 0;
  for (const s of profile.stages) {
    if (elapsedSec < t + s.sec) return from + ((s.to - from) * (elapsedSec - t)) / s.sec;
    from = s.to;
    t += s.sec;
  }
  return from;
}

// A profile may name its own phases by elapsed seconds; the rest follows the 10,000 RPS limit of the SLOs.
export function phaseAt(profile, elapsedSec) {
  for (const ph of profile.phases || []) {
    if (elapsedSec < ph.until) return ph.name;
  }
  return profile.phases ? 'within-slo' : targetRateAt(profile, elapsedSec) <= SLO_RPS_LIMIT ? 'within-slo' : 'beyond-slo';
}

export function totalSeconds(profile) {
  return profile.stages.reduce((sum, s) => sum + s.sec, 0);
}

export function preAllocatedVUs(rps, avgSec = AVG_INFLIGHT_SEC, safety = 2) {
  return Math.max(1, Math.ceil(rps * avgSec * safety));
}
