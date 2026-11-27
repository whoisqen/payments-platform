{{- define "payments-edge.labels" -}}
app.kubernetes.io/name: payments-edge
app.kubernetes.io/part-of: payments-platform
{{- end -}}

{{/* Istio names the proxy Deployment and Service <gateway>-<gatewayClassName> */}}
{{- define "payments-edge.proxyName" -}}
payments-edge-{{ .Values.gateway.className }}
{{- end -}}

{{/* Envoy ratelimit descriptors share one shape for every class */}}
{{- define "payments-edge.localBucket" -}}
token_bucket:
  max_tokens: {{ .maxTokens }}
  tokens_per_fill: {{ .tokensPerFill }}
  fill_interval: {{ .fillInterval }}
{{- end -}}

{{/* Lua source run first: drop client copies of edge headers, set the rate key from the caller's credential */}}
{{- define "payments-edge.trustLua" -}}
{{- $r := .Values.routing -}}
local strip = { {{ $r.rateKeyHeader | quote }}, {{ .Values.classes.header | quote }} }

-- Two 32-bit string hashes kept below 2^53 so double arithmetic stays exact without the bit library
local function rate_key(s)
  local a, b = 5381, 0
  for i = 1, #s do
    local c = string.byte(s, i)
    a = (a * 33 + c) % 4294967296
    b = (b * 65599 + c) % 4294967296
  end
  return string.format("%04x%04x%04x%04x", math.floor(a / 65536), a % 65536, math.floor(b / 65536), b % 65536)
end

local function route_and_ip(handle, headers)
  local path = string.match(headers:get(":path") or "/", "^[^?]*")
  local route = string.match(path, "^/[^/]*/?[^/]*/?[^/]*") or "/"
  local addr = handle:streamInfo():downstreamRemoteAddress() or ""
  return route .. "|" .. (string.match(addr, "^(.*):%d+$") or addr)
end

function envoy_on_request(handle)
  local headers = handle:headers()
  for _, name in ipairs(strip) do
    headers:remove(name)
  end
  local key = headers:get({{ $r.apiKeyHeader | quote }})
  local source
  if key ~= nil and key ~= "" then
    source = "k:" .. key
  else
    local auth = headers:get({{ $r.authHeader | quote }})
    if auth ~= nil and auth ~= "" then
      source = "a:" .. auth
    else
      source = "r:" .. route_and_ip(handle, headers)
    end
  end
  headers:replace({{ $r.rateKeyHeader | quote }}, rate_key(source))
end
{{- end -}}

{{/* Lua source: cell guard, class assignment by path and Retry-After on every 429 */}}
{{- define "payments-edge.lua" -}}
local cells = { {{- range .Values.routing.cells }}[{{ .name | quote }}] = true, {{ end -}} }
local list_prefixes = { {{- range .Values.classes.list.prefixes }}{{ . | quote }}, {{ end -}} }
local read_prefixes = { {{- range .Values.classes.read.prefixes }}{{ . | quote }}, {{ end -}} }
local read_methods = { {{- range .Values.classes.read.methods }}[{{ . | quote }}] = true, {{ end -}} }

local function under(path, prefixes)
  for _, p in ipairs(prefixes) do
    if path == p or string.sub(path, 1, #p + 1) == p .. "/" then
      return true
    end
  end
  return false
end

function envoy_on_request(handle)
  local headers = handle:headers()
  local cell = headers:get({{ .Values.routing.cellHeader | quote }})
  if cell == nil or not cells[cell] then
    handle:respond({[":status"] = "503", ["content-type"] = "text/plain"}, "cell unresolved")
    return
  end
  local path = string.match(headers:get(":path") or "/", "^[^?]*")
  local class = "payments"
  if under(path, list_prefixes) then
    class = "list"
  elseif read_methods[headers:get(":method")] and under(path, read_prefixes) then
    class = "read"
  end
  headers:replace({{ .Values.classes.header | quote }}, class)
end

function envoy_on_response(handle)
  local headers = handle:headers()
  if headers:get(":status") == "429" and headers:get("retry-after") == nil then
    headers:add("retry-after", {{ .Values.rateLimit.retryAfterSeconds | quote }})
  end
end
{{- end -}}

{{/* Router host of one cell: the explicit host, or the default name under routing.clusterDomain */}}
{{- define "payments-edge.cellHost" -}}
{{- if .cell.host -}}{{ .cell.host }}
{{- else -}}{{ printf "router.payments.svc.%s.%s" .cell.name (required "routing.clusterDomain is required for a cell without host" .root.Values.routing.clusterDomain) }}
{{- end -}}
{{- end }}
