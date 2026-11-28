# One OTLP export request (resourceLogs/scopeLogs/logRecords) in, one event per log record out.
# Field contract of logs-app-*: @timestamp, body, severity.text, resource.<attribute>, attributes.<attribute>, traceId, spanId.
require "json"

SEVERITIES = [[21, "FATAL"], [17, "ERROR"], [13, "WARN"], [9, "INFO"], [5, "DEBUG"], [1, "TRACE"]].freeze
LEVEL_IN_BODY = /(?:"level"\s*:\s*"|\blevel=|^\S+\s+)(trace|debug|info|warn|warning|error|fatal|critical)\b/i
# 13 to 19 digits, single spaces or dashes between them, not part of a longer number
PAN = /(?<![0-9])[0-9](?:[ -]?[0-9]){12,18}(?![0-9])/

def register(params)
  @prefix = params.fetch("data_stream_prefix", "logs-app-")
  @fallback = params.fetch("fallback_environment", "unknown")
  @drop_debug = Array(params.fetch("drop_debug_environments", []))
end

def luhn?(digits)
  sum = 0
  digits.reverse.each_char.with_index do |c, i|
    d = c.ord - 48
    if i.odd?
      d *= 2
      d -= 9 if d > 9
    end
    sum += d
  end
  (sum % 10).zero?
end

# Second line after the collector's redaction: keeps the first 6 and the last 4 digits of a Luhn-valid number
def mask(text)
  return text unless text.is_a?(String) && text =~ /[0-9]{4}/
  text.gsub(PAN) do |m|
    digits = m.delete(" -")
    luhn?(digits) ? digits[0, 6] + ("*" * (digits.length - 10)) + digits[-4, 4] : m
  end
end

def mask_deep(value)
  case value
  when String then mask(value)
  when Array then value.map { |v| mask_deep(v) }
  when Hash then value.each_with_object({}) { |(k, v), h| h[k] = mask_deep(v) }
  else value
  end
end

def any_value(v)
  return nil unless v.is_a?(Hash)
  if v.key?("stringValue") then v["stringValue"]
  elsif v.key?("boolValue") then v["boolValue"]
  elsif v.key?("intValue") then Integer(v["intValue"].to_s, 10) rescue v["intValue"]
  elsif v.key?("doubleValue") then v["doubleValue"]
  elsif v.key?("arrayValue") then Array((v["arrayValue"] || {})["values"]).map { |x| any_value(x) }
  elsif v.key?("kvlistValue") then key_values((v["kvlistValue"] || {})["values"])
  elsif v.key?("bytesValue") then v["bytesValue"]
  end
end

def key_values(list)
  Array(list).each_with_object({}) do |a, h|
    h[a["key"]] = any_value(a["value"]) if a.is_a?(Hash) && a["key"].is_a?(String)
  end
end

def timestamp(record)
  ns = [record["timeUnixNano"], record["observedTimeUnixNano"]].map { |t| t.to_s.to_i }.find(&:positive?)
  return LogStash::Timestamp.now unless ns
  LogStash::Timestamp.at(ns / 1_000_000_000, (ns % 1_000_000_000) / 1000.0)
end

def severity(record, body)
  number = record["severityNumber"].to_i
  text = record["severityText"].to_s
  text = (SEVERITIES.find { |n, _| number >= n } || [0, ""])[1] if text.empty? && number.positive?
  text = (body =~ LEVEL_IN_BODY ? Regexp.last_match(1) : "") if text.empty? && body.is_a?(String)
  text = { "WARNING" => "WARN", "CRITICAL" => "FATAL" }.fetch(text.upcase, text.upcase)
  { "text" => text.empty? ? "UNSPECIFIED" : text, "number" => number }
end

def environment(resource)
  env = resource["deployment.environment.name"].to_s.downcase.gsub(/[^a-z0-9-]/, "-").gsub(/\A-+|-+\z/, "")
  env.empty? ? @fallback : env
end

def debug?(sev, attributes)
  (sev["number"] >= 1 && sev["number"] <= 8) || %w[TRACE DEBUG].include?(sev["text"]) || attributes["log.retention"] == "debug"
end

def filter(event)
  out = []
  Array(event.get("resourceLogs")).each do |rl|
    next unless rl.is_a?(Hash)
    resource = mask_deep(key_values((rl["resource"] || {})["attributes"]))
    env = environment(resource)
    Array(rl["scopeLogs"]).each do |sl|
      next unless sl.is_a?(Hash)
      scope = sl["scope"].is_a?(Hash) ? sl["scope"] : {}
      Array(sl["logRecords"]).each do |rec|
        next unless rec.is_a?(Hash)
        body = any_value(rec["body"])
        body = body.to_json unless body.nil? || body.is_a?(String)
        attributes = mask_deep(key_values(rec["attributes"]))
        sev = severity(rec, body)
        next if debug?(sev, attributes) && @drop_debug.include?(env)
        doc = {
          "@timestamp" => timestamp(rec),
          "body" => mask(body.to_s),
          "severity" => sev,
          "resource" => resource,
          "attributes" => attributes,
          "instrumentationScope" => { "name" => scope["name"].to_s, "version" => scope["version"].to_s }
        }
        doc["traceId"] = rec["traceId"] unless rec["traceId"].to_s.empty?
        doc["spanId"] = rec["spanId"] unless rec["spanId"].to_s.empty?
        e = LogStash::Event.new(doc)
        e.set("[@metadata][target]", @prefix + env)
        out << e
      end
    end
  end
  out
end

test "flattens one record per log record with the resource and the data stream" do
  parameters { { "drop_debug_environments" => ["prod"] } }
  in_event do
    { "resourceLogs" => [{ "resource" => { "attributes" => [
      { "key" => "service.name", "value" => { "stringValue" => "router" } },
      { "key" => "deployment.environment.name", "value" => { "stringValue" => "stage" } }] },
      "scopeLogs" => [{ "logRecords" => [
        { "timeUnixNano" => "1700000000123456789", "severityNumber" => 17, "body" => { "stringValue" => "a" } },
        { "severityText" => "info", "body" => { "stringValue" => "b" } }] }] }] }
  end
  expect("two events") { |events| events.size == 2 }
  expect("resource kept") { |events| events.all? { |e| e.get("[resource][service.name]") == "router" } }
  expect("target") { |events| events.all? { |e| e.get("[@metadata][target]") == "logs-app-stage" } }
  expect("severity") { |events| events.map { |e| e.get("[severity][text]") } == %w[ERROR INFO] }
end

test "masks a Luhn-valid number and leaves other numbers alone" do
  parameters { {} }
  in_event do
    { "resourceLogs" => [{ "resource" => { "attributes" => [] }, "scopeLogs" => [{ "logRecords" => [
      { "body" => { "stringValue" => "card 4111 1111 1111 1111 order 1234567890123" } }] }] }] }
  end
  expect("masked") { |events| events.first.get("body") == "card 411111******1111 order 1234567890123" }
  expect("fallback environment") { |events| events.first.get("[@metadata][target]") == "logs-app-unknown" }
end

test "drops debug records in a listed environment only" do
  parameters { { "drop_debug_environments" => ["prod"] } }
  in_event do
    { "resourceLogs" => [
      { "resource" => { "attributes" => [{ "key" => "deployment.environment.name", "value" => { "stringValue" => "prod" } }] },
        "scopeLogs" => [{ "logRecords" => [{ "severityNumber" => 5, "body" => { "stringValue" => "x" } },
                                           { "attributes" => [{ "key" => "log.retention", "value" => { "stringValue" => "debug" } }] }] }] },
      { "resource" => { "attributes" => [{ "key" => "deployment.environment.name", "value" => { "stringValue" => "dev" } }] },
        "scopeLogs" => [{ "logRecords" => [{ "severityNumber" => 5, "body" => { "stringValue" => "y" } }] }] }] }
  end
  expect("only the dev record") { |events| events.size == 1 && events.first.get("body") == "y" }
end
