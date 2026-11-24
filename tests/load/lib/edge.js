// Paths and header names of the edge as the payments-edge chart routes them; change them here only.
export const HEADERS = { merchant: 'x-merchant-id', retryAfter: 'Retry-After' };

export const CLASSES = ['payments', 'read', 'list'];

export const PATHS = {
  create: () => '/payments',
  confirm: (id) => `/payments/${id}/confirm`,
  status: (id) => `/payments/${id}`,
  methods: () => '/payments/session_tokens',
  webhook: (merchantId) => `/webhooks/${merchantId}/dummy`,
  refund: () => '/refunds',
  list: () => '/payments/list?limit=20',
  report: () => '/reports/payments',
};

// The 7-calls-per-payment table plus list and report calls at about 10% of the traffic.
export const EDGE_MIX = [
  { type: 'create', weight: 1 },
  { type: 'confirm', weight: 1 },
  { type: 'status', weight: 2 },
  { type: 'methods', weight: 1 },
  { type: 'webhook', weight: 1 },
  { type: 'refund', weight: 1 },
  { type: 'list', weight: 0.5 },
  { type: 'report', weight: 0.3 },
];

export function needsPaymentId(type) {
  return ['confirm', 'status', 'webhook', 'refund', 'methods'].includes(type);
}

// The class comes from the path, the way the edge decides what to shed.
export function classifyRequest(method, path) {
  const p = path.split('?')[0];
  if (p === '/payments/list' || p === '/refunds/list' || p.startsWith('/reports')) return 'list';
  if (method === 'GET' && /^\/payments\/[^/]+$/.test(p)) return 'read';
  if (method === 'POST' && p === '/payments/session_tokens') return 'read';
  return 'payments';
}

export function buildEdgeRequest(type, cfg, merchantId, paymentId) {
  const headers = { 'Content-Type': 'application/json', 'api-key': cfg.apiKey, [HEADERS.merchant]: merchantId };
  const json = (o) => JSON.stringify(o);
  let method = 'GET';
  let path;
  let body = null;
  switch (type) {
    case 'create':
      method = 'POST';
      path = PATHS.create();
      body = json({ amount: 1000, currency: 'EUR', confirm: false, capture_method: 'automatic' });
      headers['Idempotency-Key'] = cfg.idempotencyKey();
      break;
    case 'confirm':
      method = 'POST';
      path = PATHS.confirm(paymentId);
      body = json({ payment_token: cfg.paymentToken });
      break;
    case 'status':
      path = PATHS.status(paymentId);
      break;
    case 'methods':
      method = 'POST';
      path = PATHS.methods();
      body = json({ payment_id: paymentId });
      break;
    case 'webhook':
      method = 'POST';
      path = PATHS.webhook(merchantId);
      body = json({ event_type: 'payment_succeeded', object_reference_id: paymentId });
      break;
    case 'refund':
      method = 'POST';
      path = PATHS.refund();
      body = json({ payment_id: paymentId, amount: 500 });
      break;
    case 'list':
      path = PATHS.list();
      break;
    case 'report':
      path = PATHS.report();
      break;
    default:
      throw new Error(`unknown request type ${type}`);
  }
  return { method, path, url: `${cfg.baseUrl}${path}`, body, headers, klass: classifyRequest(method, path) };
}
