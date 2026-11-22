export const DEFAULTS = { minMs: 300, maxMs: 1500, errorRate: 0, errorStatus: 503, timeoutRate: 0, timeoutMs: 20000 };

export function validate(cfg) {
  const c = { ...DEFAULTS, ...cfg };
  for (const k of ['minMs', 'maxMs', 'timeoutMs']) {
    if (!Number.isFinite(c[k]) || c[k] < 0) throw new Error(`${k} must be a non-negative number`);
  }
  if (c.minMs > c.maxMs) throw new Error('minMs must not exceed maxMs');
  for (const k of ['errorRate', 'timeoutRate']) {
    if (!Number.isFinite(c[k]) || c[k] < 0 || c[k] > 1) throw new Error(`${k} must be within [0, 1]`);
  }
  if (c.errorRate + c.timeoutRate > 1) throw new Error('errorRate + timeoutRate must not exceed 1');
  return c;
}

export function fromEnv(env) {
  const num = (k) => (env[k] === undefined ? undefined : Number(env[k]));
  const raw = {
    minMs: num('PSP_LATENCY_MIN_MS'),
    maxMs: num('PSP_LATENCY_MAX_MS'),
    errorRate: num('PSP_ERROR_RATE'),
    errorStatus: num('PSP_ERROR_STATUS'),
    timeoutRate: num('PSP_TIMEOUT_RATE'),
    timeoutMs: num('PSP_TIMEOUT_MS'),
  };
  return validate(Object.fromEntries(Object.entries(raw).filter(([, v]) => v !== undefined)));
}

// A timeout holds the connection for timeoutMs and then drops it, like a PSP that never answers.
export function decide(cfg, rng = Math.random) {
  const roll = rng();
  if (roll < cfg.timeoutRate) return { kind: 'timeout', delayMs: cfg.timeoutMs };
  const delayMs = Math.round(cfg.minMs + rng() * (cfg.maxMs - cfg.minMs));
  if (roll < cfg.timeoutRate + cfg.errorRate) return { kind: 'error', delayMs, status: cfg.errorStatus };
  return { kind: 'ok', delayMs };
}
