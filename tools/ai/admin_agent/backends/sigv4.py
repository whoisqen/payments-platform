"""AWS Signature Version 4 for one HTTPS request, standard library only (the agent ships without botocore on its path)."""
import datetime
import hashlib
import hmac
import urllib.parse


def _hmac(key, msg):
    return hmac.new(key, msg.encode("utf-8"), hashlib.sha256).digest()


def sign(method, url, body, creds, region, service, now=None, payload_header=True):
    """Headers that authenticate `method url body` with the assumed-role credentials (AccessKeyId, SecretAccessKey, SessionToken)."""
    now = now or datetime.datetime.now(datetime.timezone.utc)
    amz_date, day = now.strftime("%Y%m%dT%H%M%SZ"), now.strftime("%Y%m%d")
    u = urllib.parse.urlsplit(url)
    host = u.hostname if u.port in (None, 443) else f"{u.hostname}:{u.port}"
    payload_hash = hashlib.sha256(body).hexdigest()
    headers = {"host": host, "x-amz-date": amz_date}
    if payload_header:
        headers["x-amz-content-sha256"] = payload_hash
    if creds.get("SessionToken"):
        headers["x-amz-security-token"] = creds["SessionToken"]
    names = sorted(headers)
    path = urllib.parse.quote(u.path or "/", safe="/-_.~")
    query = "&".join(f"{urllib.parse.quote(k, safe='-_.~')}={urllib.parse.quote(v, safe='-_.~')}"
                     for k, v in sorted(urllib.parse.parse_qsl(u.query, keep_blank_values=True)))
    canonical = "\n".join([method, path, query, "".join(f"{n}:{headers[n].strip()}\n" for n in names), ";".join(names), payload_hash])
    scope = f"{day}/{region}/{service}/aws4_request"
    to_sign = "\n".join(["AWS4-HMAC-SHA256", amz_date, scope, hashlib.sha256(canonical.encode("utf-8")).hexdigest()])
    key = _hmac(_hmac(_hmac(_hmac(("AWS4" + creds["SecretAccessKey"]).encode("utf-8"), day), region), service), "aws4_request")
    signature = hmac.new(key, to_sign.encode("utf-8"), hashlib.sha256).hexdigest()
    headers["Authorization"] = (f"AWS4-HMAC-SHA256 Credential={creds['AccessKeyId']}/{scope}, SignedHeaders={';'.join(names)}, "
                                f"Signature={signature}")
    del headers["host"]
    return headers
