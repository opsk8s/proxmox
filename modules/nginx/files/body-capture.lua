-- Captures request + response bodies of JSON API POSTs proxied to the
-- LLM upstream. One JSON line per request in /var/log/nginx/bodies.log.
-- Correlate with the nginx-access-* analytics via request_id.
-- Every fallible step is pcall-guarded: failures only reach the nginx
-- error log, never the proxied request.
local cjson = require "cjson.safe"
local LOG = "/var/log/nginx/bodies.log"
-- Memory ceiling for ONE in-flight accumulation. Protects the proxy
-- from a runaway/streaming response OOMing it; bodies are stored
-- uncapped below this (flagged truncated if the ceiling is hit).
local MAX_ACCUM = 64 * 1024 * 1024

local function log_error(...)
  ngx.log(ngx.ERR, "[body-capture] ", ...)
end

local function read_request_body()
  ngx.req.read_body()
  local data = ngx.req.get_body_data()
  if data then
    return data
  end
  -- Body spilled to a temp file (client_body_buffer_size exceeded)
  local file = ngx.req.get_body_file()
  if not file then
    return ""
  end
  local f, err = io.open(file, "rb")
  if not f then
    log_error("cannot read body file ", file, ": ", err)
    return ""
  end
  local buf = f:read("*a")
  f:close()
  return buf or ""
end

local phase = ngx.get_phase()

if phase == "access" then
  local ct = ngx.var.http_content_type or ""
  ngx.ctx.bc = {
    active = ngx.req.get_method() == "POST"
        and string.find(ct, "json", 1, true) ~= nil,
    req_body = "",
    chunks = {},
    size = 0,
    overflow = false,
  }
  if ngx.ctx.bc.active then
    local ok, body = pcall(read_request_body)
    if ok then
      ngx.ctx.bc.req_body = body
    else
      log_error("request body read failed: ", body)
    end
  end

elseif phase == "body_filter" then
  local c = ngx.ctx.bc
  if not (c and c.active) then
    return
  end
  local chunk = ngx.arg[1]
  if chunk and #chunk > 0 and not c.overflow then
    if c.size + #chunk > MAX_ACCUM then
      c.overflow = true
      log_error("response body exceeded ", MAX_ACCUM,
                " bytes, capture truncated for ", ngx.var.request_id)
    else
      c.chunks[#c.chunks + 1] = chunk
      c.size = c.size + #chunk
    end
  end

elseif phase == "log" then
  local c = ngx.ctx.bc
  if not (c and c.active) then
    return
  end
  local rec = {
    time_local  = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    host        = ngx.var.host,
    request_id  = ngx.var.request_id,
    remote_addr = ngx.var.remote_addr,
    method      = ngx.req.get_method(),
    uri         = ngx.var.uri,
    upstream_addr = ngx.var.upstream_addr,
    status      = ngx.var.status,
    request_content_type  = ngx.var.http_content_type or "",
    response_content_type = ngx.var.sent_http_content_type or "",
    request_body   = c.req_body,
    response_body  = table.concat(c.chunks),
    request_body_bytes  = #c.req_body,
    response_body_bytes = c.size,
    truncated = c.overflow,
    source    = "nginx",
  }
  local json = cjson.encode(rec)
  if not json then
    log_error("encode failed for ", ngx.var.request_id)
    return
  end
  local ok, err = pcall(function()
    local f = assert(io.open(LOG, "a"))
    f:write(json, "\n")
    f:close()
  end)
  if not ok then
    log_error("write to ", LOG, " failed: ", err)
  end
end
