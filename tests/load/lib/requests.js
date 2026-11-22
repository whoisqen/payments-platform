// Endpoints follow the Hyperswitch v1 API; the card is always a pre-made test token, a PAN never appears in fixtures.
export function buildRequest(type, cfg, paymentId, sign = () => '') {
  const headers = { 'Content-Type': 'application/json', 'api-key': cfg.apiKey };
  const json = (o) => JSON.stringify(o);
  const base = cfg.baseUrl;
  switch (type) {
    case 'create': {
      const body = json({ amount: 1000, currency: 'EUR', confirm: false, capture_method: 'automatic' });
      return { method: 'POST', url: `${base}/payments`, body, headers: { ...headers, 'Idempotency-Key': cfg.idempotencyKey() } };
    }
    case 'confirm':
      return { method: 'POST', url: `${base}/payments/${paymentId}/confirm`, body: json({ payment_token: cfg.paymentToken }), headers };
    case 'status':
      return { method: 'GET', url: `${base}/payments/${paymentId}`, body: null, headers };
    case 'methods':
      return { method: 'POST', url: `${base}/payments/session_tokens`, body: json({ payment_id: paymentId }), headers };
    case 'webhook': {
      const body = json({ event_type: 'payment_succeeded', object_reference_id: paymentId });
      return { method: 'POST', url: `${base}/webhooks/${cfg.merchantId}/dummy`, body, headers: { ...headers, 'x-webhook-signature': sign(body) } };
    }
    case 'refund':
      return { method: 'POST', url: `${base}/refunds`, body: json({ payment_id: paymentId, amount: 500 }), headers };
    default:
      throw new Error(`unknown request type ${type}`);
  }
}

export function needsPayment(type) {
  return type !== 'create';
}

export function isServerError(status) {
  return status >= 500 && status <= 599;
}
