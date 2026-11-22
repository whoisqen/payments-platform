use masking::Secret;

fn bad(card: Card, req: Req) {
    // ruleid: no-pan-logging
    tracing::info!("card {}", card.card_number);
    // ruleid: no-pan-logging
    info!("card {}", card.card_number);
    // ruleid: no-pan-logging-exposed
    logger::error!(pan = card.pan, "failed");
    // ruleid: no-pan-logging
    println!("{:?}", req.card.card_cvc);
    // ruleid: no-pan-logging
    debug!("cvv {}", card.cvv);
    // ruleid: no-pan-logging-exposed
    let msg = format!("{}", card.card_number.peek());
}

fn good(card: Card, payment_id: String) {
    // ok: no-pan-logging, no-pan-logging-exposed
    tracing::info!("payment {}", payment_id);
    // ok: no-pan-logging, no-pan-logging-exposed
    info!("card {:?}", Secret::new(card.card_number));
    // ok: no-pan-logging, no-pan-logging-exposed
    info!("last4 {}", card.card_last4);
    // ok: no-pan-logging, no-pan-logging-exposed
    let pan = card.card_number;
}
