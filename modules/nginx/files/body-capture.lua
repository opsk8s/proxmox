-- Captures request + response bodies of JSON API POSTs proxied to the
-- LLM upstream, parsed into TWO structured JSON lines per request:
--   /var/log/nginx/llm-request.log  -> llm-request-body-YYYY.MM.dd
--   /var/log/nginx/llm-response.log -> llm-response-body-YYYY.MM.dd
-- (Fluent Bit on this VM ships both, see modules/nginx/ansible.yml).
--
-- The identification fields (host, time_local, remote_addr, request, status,
-- body_bytes_sent, ...) mirror the nginx-access-* json_analytics fields, so a
-- body document joins to its access record on request_id. The request is
-- parsed as an OpenAI-compatible chat-completion payload; the response as
-- either an SSE stream of chat.completion.chunk events (stream=true) or a
-- single completion JSON object (stream=false). The decoded request payload
-- is embedded in its document as an object (request_body) with
-- messages[].content part-arrays joined to text and shape-varying fields
-- (tool parameter schemas, metadata) stored as their JSON string, so
-- messages, roles and tool definitions are individually queryable; the
-- response document keeps the raw stream next to its parsed fields.
--
-- Every fallible step is pcall-guarded: failures only reach the nginx
-- error log, never the proxied request.
local cjson = require "cjson.safe"
local REQ_LOG = "/var/log/nginx/llm-request.log"
local RESP_LOG = "/var/log/nginx/llm-response.log"
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

-- Identification fields, same names as the json_analytics access log.
-- Built fresh for each document (the request and response records are
-- separate tables; sharing one would cross-contaminate them).
local function ident_fields()
  return {
    time_local = ngx.var.time_local,
    time_iso8601 = ngx.var.time_iso8601,
    host = ngx.var.host,
    request_id = ngx.var.request_id,
    remote_addr = ngx.var.remote_addr,
    remote_user = ngx.var.remote_user or "-",
    request = ngx.var.request,
    status = ngx.var.status,
    body_bytes_sent = ngx.var.body_bytes_sent,
    request_time = ngx.var.request_time,
    http_referrer = ngx.var.http_referer,
    http_user_agent = ngx.var.http_user_agent,
    http_x_forwarded_for = ngx.var.http_x_forwarded_for,
    upstream_addr = ngx.var.upstream_addr,
    upstream_response_time = ngx.var.upstream_response_time,
    upstream_status = ngx.var.upstream_status,
    method = ngx.req.get_method(),
    uri = ngx.var.uri,
  }
end

local function write_line(path, rec)
  local json = cjson.encode(rec)
  if not json then
    log_error("encode failed for ", path)
    return
  end
  local ok, err = pcall(function()
    local f = assert(io.open(path, "a"))
    f:write(json, "\n")
    f:close()
  end)
  if not ok then
    log_error("write to ", path, " failed: ", err)
  end
end

-- Message content in the OpenAI spec is a union: a plain string, or an
-- array of content parts (Qwen Code sends user turns as
-- [{type:text, text:...}]). The index mapping needs one type, so part
-- arrays are joined into a single string: text parts concatenated (as the
-- client renders them), non-text parts kept inline as their JSON form so
-- nothing is silently dropped.
local function join_content(parts)
  local out = {}
  for _, p in ipairs(parts) do
    if type(p) == "string" then
      out[#out + 1] = p
    elseif type(p) == "table" then
      if type(p.text) == "string" then
        out[#out + 1] = p.text
      else
        local j = cjson.encode(p)
        out[#out + 1] = j or p.type or "?"
      end
    end
  end
  return table.concat(out)
end

-- Shape-unstable values (tool parameter schemas, arbitrary metadata) become
-- their JSON string form: OpenSearch has no flattened type, and one string
-- type keeps the mapping stable no matter what the payload contains.
local function to_json(v)
  if type(v) == "table" then
    local j = cjson.encode(v)
    return j or "?"
  end
  return v
end

-- Parse an OpenAI-compatible request payload. cjson.safe.decode returns nil
-- (never throws) for anything that is not JSON, so a parse failure only sets
-- parse_error and leaves the parsed fields absent. On success the decoded
-- object is returned as request_body (content unions normalized), so the
-- index stores the payload as a structured object, not a raw string.
local function parse_request(body)
  local out = {}
  local obj = cjson.decode(body)
  if type(obj) ~= "table" then
    out.parse_error = true
    return out
  end
  out.model = obj.model
  out.stream = obj.stream
  out.temperature = obj.temperature
  out.top_p = obj.top_p
  out.max_tokens = obj.max_tokens
  out.frequency_penalty = obj.frequency_penalty
  out.presence_penalty = obj.presence_penalty
  if type(obj.tools) == "table" then
    out.tools_count = #obj.tools
  end
  if type(obj.messages) == "table" then
    for _, m in ipairs(obj.messages) do
      if type(m) == "table" and type(m.content) == "table" then
        m.content = join_content(m.content)
      end
    end
    out.messages_count = #obj.messages
    for _, m in ipairs(obj.messages) do
      if type(m) == "table" and type(m.content) == "string" then
        if m.role == "system" and out.system_prompt == nil then
          out.system_prompt = m.content
        elseif m.role == "user" then
          -- last user turn is the current prompt
          out.user_message = m.content
        end
      end
    end
  end
  if type(obj.tools) == "table" then
    for _, t in ipairs(obj.tools) do
      if type(t) == "table" and type(t["function"]) == "table" then
        t["function"].parameters = to_json(t["function"].parameters)
      end
    end
  end
  obj.stop = to_json(obj.stop)
  obj.metadata = to_json(obj.metadata)
  obj.response_format = to_json(obj.response_format)
  out.request_body = obj
  return out
end

local function usage_fields(o, out)
  if type(o.usage) == "table" then
    out.usage_prompt_tokens = o.usage.prompt_tokens
    out.usage_completion_tokens = o.usage.completion_tokens
    out.usage_total_tokens = o.usage.total_tokens
  end
end

-- Parse the response body: an SSE stream of `data: {...}` chunk events
-- (llama-server with stream=true; the stream may open with an empty `:`
-- comment line) or a single completion JSON object (stream=false, or a JSON
-- error body). Streaming content/reasoning deltas are accumulated in arrays
-- and joined ONCE -- per-chunk string concatenation would be O(n^2) on
-- multi-MB streams.
local function parse_response(body)
  local out = { stream = false }
  if body == "" then
    out.parse_error = true
    return out
  end
  local first = body:match("^[^\r\n]*")
  if first:sub(1, 6) == "data: " or first:sub(1, 1) == ":" then
    out.stream = true
    local content_parts = {}
    local reasoning_parts = {}
    local chunk_count = 0
    for line in (body .. "\n"):gmatch("(.-)\n") do
      if line:sub(1, 6) == "data: " then
        local payload = line:sub(7)
        if payload == "[DONE]" then
          out.done = true
        else
          chunk_count = chunk_count + 1
          local o = cjson.decode(payload)
          if type(o) == "table" then
            -- metadata comes from the first chunk, not re-read afterwards
            out.completion_id = out.completion_id or o.id
            out.model = out.model or o.model
            out.created = out.created or o.created
            out.system_fingerprint = out.system_fingerprint or o.system_fingerprint
            usage_fields(o, out)
            local ch = o.choices and o.choices[1]
            if type(ch) == "table" then
              local d = ch.delta
              if type(d) == "table" then
                if type(d.content) == "string" then
                  content_parts[#content_parts + 1] = d.content
                end
                if type(d.reasoning_content) == "string" then
                  reasoning_parts[#reasoning_parts + 1] = d.reasoning_content
                end
              end
              if ch.finish_reason then
                out.finish_reason = ch.finish_reason -- last non-null wins
              end
            end
          end
        end
      end
    end
    out.chunk_count = chunk_count
    if #content_parts > 0 then
      out.content = table.concat(content_parts)
    end
    if #reasoning_parts > 0 then
      out.reasoning_content = table.concat(reasoning_parts)
    end
    if chunk_count == 0 then
      out.parse_error = true
    end
    return out
  end

  -- Non-streaming: one completion JSON (or a JSON/plain error body).
  local o = cjson.decode(body)
  if type(o) == "table" then
    out.completion_id = o.id
    out.model = o.model
    out.created = o.created
    out.system_fingerprint = o.system_fingerprint
    usage_fields(o, out)
    local ch = o.choices and o.choices[1]
    if type(ch) == "table" then
      if type(ch.message) == "table" and type(ch.message.content) == "string" then
        out.content = ch.message.content
      end
      if ch.finish_reason then
        out.finish_reason = ch.finish_reason
      end
    end
    if type(o.error) == "table" and type(o.error.message) == "string" then
      out.error_message = o.error.message
    end
  else
    out.parse_error = true
  end
  return out
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
  local ok, err = pcall(function()
    local resp_raw = table.concat(c.chunks)

    local req = ident_fields()
    for k, v in pairs(parse_request(c.req_body)) do
      req[k] = v
    end
    if req.parse_error then
      -- not JSON: the object is absent, keep the raw payload searchable
      req.request_body_raw = c.req_body
    end
    req.request_content_type = ngx.var.http_content_type or ""
    req.response_content_type = ngx.var.sent_http_content_type or ""
    req.request_body_bytes = #c.req_body
    req.truncated = c.overflow
    req.source = "nginx"
    write_line(REQ_LOG, req)

    local resp = ident_fields()
    for k, v in pairs(parse_response(resp_raw)) do
      resp[k] = v
    end
    resp.request_content_type = ngx.var.http_content_type or ""
    resp.response_content_type = ngx.var.sent_http_content_type or ""
    resp.response_body = resp_raw
    resp.response_body_bytes = c.size
    resp.truncated = c.overflow
    resp.source = "nginx"
    write_line(RESP_LOG, resp)
  end)
  if not ok then
    log_error("capture failed: ", err)
  end
end
