// Share of traffic sent by the hot merchant: base until rampStart, linear to peak over rampSec, then peak.
export function hotShare(elapsedSec, p) {
  if (elapsedSec <= p.rampStart) return p.base;
  if (elapsedSec >= p.rampStart + p.rampSec) return p.peak;
  return p.base + ((p.peak - p.base) * (elapsedSec - p.rampStart)) / p.rampSec;
}

export function sharePhase(share, p) {
  if (share <= p.base + 0.005) return 'baseline';
  if (share >= p.peak - 0.005) return 'hot';
  return 'ramp';
}

// r in [0, 1): the lowest `share` of the range is the hot merchant, the rest is spread evenly over the others.
export function pickMerchant(r, share, hot, others) {
  if (r < share) return { id: hot, role: 'hot' };
  const i = Math.min(others.length - 1, Math.floor(((r - share) / (1 - share)) * others.length));
  return { id: others[i], role: 'other' };
}

// Phase of the shedding ramp by planned rate relative to the capacity of the gateway.
export function loadPhase(rate, capacity) {
  if (rate <= capacity) return 'within';
  if (rate <= capacity * 1.5) return 'over';
  return 'heavy';
}

// Profile in the shape of profiles.js: ramp to capacity, then 1.5x and 2.5x of it, each held.
export function shedProfile(capacity) {
  const to = (k) => Math.round(capacity * k);
  return {
    stages: [
      { sec: 60, to: to(1) },
      { sec: 60, to: to(1) },
      { sec: 30, to: to(1.5) },
      { sec: 90, to: to(1.5) },
      { sec: 30, to: to(2.5) },
      { sec: 90, to: to(2.5) },
      { sec: 30, to: 0 },
    ],
  };
}
