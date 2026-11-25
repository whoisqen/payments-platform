// Mirrors tests/chaos/lib/guard.py; a unit test keeps the two in step.
// k6 has no URL global: take the host from the authority part by hand
export function hostOf(url) {
  const m = /^[a-z][a-z0-9+.-]*:\/\/(?:[^@/?#]*@)?(\[[^\]]*\]|[^:/?#]*)/i.exec(String(url));
  return m ? m[1].toLowerCase() : '';
}

export const ALLOWED_ENVIRONMENTS = ['stage'];

export function guardReasons(env) {
  const reasons = [];
  if (!ALLOWED_ENVIRONMENTS.includes(env.TARGET_ENV)) reasons.push(`environment '${env.TARGET_ENV}' is not allowed`);
  if (env.FREEZE === 'true') reasons.push('change freeze is active');
  if (Number(env.OPEN_INCIDENTS || 0) > 0) reasons.push('an incident is open');
  if (!env.BASE_URL) reasons.push('BASE_URL is not set');
  else if (/prod|cde/i.test(hostOf(env.BASE_URL))) reasons.push('BASE_URL host looks like prod or the CDE');
  return reasons;
}

export function assertStage(env) {
  const reasons = guardReasons(env);
  if (reasons.length) throw new Error(`refusing to run: ${reasons.join('; ')}`);
}
