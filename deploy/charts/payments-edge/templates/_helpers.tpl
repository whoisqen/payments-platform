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
