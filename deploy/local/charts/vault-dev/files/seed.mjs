// Seeds the dev-mode Vault with generated keys in the KV layout the charts read, then re-seeds whenever Vault comes back empty.
import { generateKeyPairSync, randomBytes } from 'node:crypto';
import { readFileSync, rmSync, writeFileSync } from 'node:fs';

const env = process.env;
const vault = env.VAULT_ADDR;
const token = env.VAULT_TOKEN;
const environment = env.SEED_ENVIRONMENT;
const cells = env.SEED_CELLS.split(',');
const mount = env.SEED_KV_MOUNT;
const sa = '/var/run/secrets/kubernetes.io/serviceaccount';
const kube = 'https://kubernetes.default.svc';
const ready = '/tmp/seeded';
const services = ['router', 'drainer', 'scheduler'];

const hex = (n) => randomBytes(n).toString('hex');
const word = (n) => randomBytes(n).toString('base64url');
const rsa = () => {
  const k = generateKeyPairSync('rsa', {
    modulusLength: 2048,
    publicKeyEncoding: { type: 'spki', format: 'pem' },
    privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
  });
  return { public: k.publicKey, private: k.privateKey };
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const log = (msg) => console.log(JSON.stringify({ ts: new Date().toISOString(), msg }));

function generate() {
  return {
    app: {
      master_enc_key: hex(32),
      admin_api_key: word(24),
      jwt_secret: word(32),
      api_keys_hash_key: hex(32),
      user_auth_encryption_key: hex(32),
    },
    router: rsa(),
    locker: rsa(),
    tunnel: rsa(),
    lockerMasterKey: hex(32),
    postgres: { admin: word(24), hs_app: word(24), hs_migrator: word(24), locker_app: word(24), locker_migrator: word(24) },
    redis: { router: word(24), drainer: word(24), scheduler: word(24), ratelimit: word(24) },
    grafana: word(18),
  };
}

async function kubeCall(method, path, body) {
  const res = await fetch(`${kube}${path}`, {
    method,
    headers: { authorization: `Bearer ${readFileSync(`${sa}/token`, 'utf8')}`, 'content-type': 'application/json' },
    body: body && JSON.stringify(body),
  });
  return { status: res.status, body: res.status < 300 ? await res.json() : await res.text() };
}

// The material lives in a Secret of this namespace; created once, read on every later start
async function material() {
  const path = `/api/v1/namespaces/${env.POD_NAMESPACE}/secrets/${env.SEED_MATERIAL_SECRET}`;
  for (;;) {
    const got = await kubeCall('GET', path);
    if (got.status === 200) return JSON.parse(Buffer.from(got.body.data['material.json'], 'base64').toString());
    if (got.status !== 404) throw new Error(`read material: ${got.status} ${got.body}`);
    const created = await kubeCall('POST', `/api/v1/namespaces/${env.POD_NAMESPACE}/secrets`, {
      metadata: { name: env.SEED_MATERIAL_SECRET, labels: { 'app.kubernetes.io/part-of': 'payments-platform' } },
      type: 'Opaque',
      data: { 'material.json': Buffer.from(JSON.stringify(generate())).toString('base64') },
    });
    if (created.status !== 201 && created.status !== 409) throw new Error(`create material: ${created.status} ${created.body}`);
    log('material generated');
  }
}

async function vaultCall(method, path, body) {
  const res = await fetch(`${vault}/v1/${path}`, {
    method,
    headers: { 'x-vault-token': token, 'content-type': 'application/json' },
    body: body && JSON.stringify(body),
  });
  if (res.status >= 300 && !(method === 'GET' && res.status === 404)) throw new Error(`${method} ${path}: ${res.status} ${await res.text()}`);
  return res.status === 204 ? {} : res.json().catch(() => ({}));
}

function kv(m) {
  const out = {};
  for (const cell of cells) {
    const base = `${environment}/${cell}`;
    out[`${base}/shared/app`] = m.app;
    // Router encrypts to the locker key and decrypts with its own; the locker does the reverse with the tenant public key
    out[`${base}/shared/locker`] = {
      vault_encryption_key: m.locker.public,
      vault_private_key: m.router.private,
      tunnel_private_key: m.tunnel.private,
    };
    for (const svc of services) {
      out[`${base}/${svc}/database`] = { password: m.postgres.hs_app };
      out[`${base}/${svc}/redis`] = { password: m.redis[svc] };
    }
  }
  out[`${environment}/locker/database`] = { password: m.postgres.locker_app };
  out[`${environment}/locker/jwe`] = { 'locker-private-key': m.locker.private };
  out[`${environment}/locker/tenants/public`] = { 'master-key': m.lockerMasterKey, 'public-key': m.router.public };
  out[`${environment}/local/postgres`] = {
    admin: m.postgres.admin,
    hs_migrator: m.postgres.hs_migrator,
    locker_migrator: m.postgres.locker_migrator,
  };
  out[`${environment}/local/redis`] = { ratelimit: m.redis.ratelimit };
  out[`${environment}/local/grafana`] = { 'admin-user': 'admin', 'admin-password': m.grafana };
  // Key of the ratelimit chart (pay/<env>/ratelimit/redis); the client sends user:password to the ACL user
  out[`pay/${environment}/ratelimit/redis`] = { auth: `ratelimit:${m.redis.ratelimit}` };
  return out;
}

async function seeded() {
  const auth = await vaultCall('GET', 'sys/auth');
  return Boolean((auth.data || auth)['kubernetes/']);
}

async function seed(m) {
  const mounts = await vaultCall('GET', 'sys/mounts');
  if (!(mounts.data || mounts)[`${mount}/`]) await vaultCall('POST', `sys/mounts/${mount}`, { type: 'kv', options: { version: '2' } });
  for (const [path, data] of Object.entries(kv(m))) await vaultCall('POST', `${mount}/data/${path}`, { data });
  await vaultCall('PUT', `sys/policies/acl/${env.SEED_ESO_ROLE}`, {
    policy: `path "${mount}/data/*" { capabilities = ["read"] }\npath "${mount}/metadata/*" { capabilities = ["read", "list"] }\n`,
  });
  // Kubernetes auth last: its presence is the marker that the seed is complete
  if (!(await seeded())) await vaultCall('POST', 'sys/auth/kubernetes', { type: 'kubernetes' });
  await vaultCall('POST', 'auth/kubernetes/config', { kubernetes_host: kube });
  await vaultCall('POST', `auth/kubernetes/role/${env.SEED_ESO_ROLE}`, {
    bound_service_account_names: [env.SEED_ESO_SERVICE_ACCOUNT],
    bound_service_account_namespaces: [env.SEED_ESO_NAMESPACE],
    audience: env.SEED_ESO_AUDIENCE,
    token_policies: [env.SEED_ESO_ROLE],
    token_ttl: '1h',
  });
}

const m = await material();
for (;;) {
  try {
    if (!(await seeded())) {
      rmSync(ready, { force: true });
      await seed(m);
      log('vault seeded');
    }
    writeFileSync(ready, 'ok');
  } catch (err) {
    log(`waiting for vault: ${err.message}`);
  }
  await sleep(10000);
}
