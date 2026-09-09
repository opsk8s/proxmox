# Project Analysis: `proxmox-server`

IaC for a 10-VM home lab on Proxmox VE: **Terraform** (bpg/proxmox + ansible provider actions) defines the VMs and triggers deployment; **Ansible** playbooks (one per module) install and configure each service; a **Makefile** mirrors the Ansible side for day-2 runs.

## 1. VM inventory

| ID  | Name          | vCPU / RAM     | Role |
|-----|---------------|----------------|------|
| 220 | dns           | 1 / 1 GB       | dnsmasq (`*.lan`) + Unbound (DoT to Cloudflare 1.1.1.1/1.0.0.1:853) |
| 202 | nginx         | 2 / 2 GB       | TLS edge (local CA), reverse proxy, lua body capture |
| 201 | elk           | 2 / 6 GB       | OpenSearch 2.x + Dashboards (no auth, trusted LAN) |
| 200 | monitoring    | 2 / 2 GB       | Prometheus 3.14 + Grafana + blackbox exporter |
| 100 | llm           | 4 / 32 GB + 500 GB virtio | 4× AMD RDNA4 passthrough (8 hostpci entries), llama.cpp ×4 (vulkan, ports 8001–8004) |
| 104 | postgres      | 8 / 16 GB      | PostgreSQL, `sysv` DSM (26.04 /dev/shm trap), 3 DBs from `database.yaml` |
| 101 | jenkins       | 2 / 8 GB       | Controller, JCasC, ~40 plugins, HTTP :8080 |
| 102 | jenkins-agent | 4 / 8 GB       | Java 21 + git + docker; SSH agent |
| 105 | taiga         | 2 / 4 GB       | Native Taiga 6.10 (back/async/protected/events/static) + local RabbitMQ |
| 103 | open-webui    | 2 / 4 GB       | uv venv (CPython 3.11), :8080, points at `app.llm.lan/v1` |

Total: **29 vCPU / 83 GB** — sizing lives in root `variables.tf` defaults (tfvars carries no sizing).

## 2. Architecture & data flows

### Requests

Client → `*.lan` (dnsmasq, 24 static records) → nginx :443 (10-year local CA at `/etc/lan-ca`, 730-day SAN leaf covering 9 `app.*.lan` names, daily renew timer) → backends. Nine `.lan` vhosts:

- `app.jenkins.lan` → jenkins :8080 (3600 s proxy timeouts)
- `app.webui.lan` → open-webui :8080
- `app.taiga.lan` → taiga :8080 (front/static), :8000 (api/admin), :8003 (media), :8888 (events/SSE with 7-day timeouts); `/_protected/` resolves via X-Accel-Redirect to the in-VM static server
- `app.llm.lan` → round-robin pool 8001–8004 (`proxy_buffering off`, `X-Request-Id`/`X-Upstream` headers, 3 lua hooks for parsed body capture → `llm-request-body-*` / `llm-response-body-*`)
- `app.kibana.lan` → dashboards :5601, `app.elastic.lan` → opensearch :9200, `grafana.lan` → :3000, `prometheus.lan` → :9090
- default server 301s to https; HSTS enabled

### LLM inference

4 systemd `llama-server-<port>.service` units, one GPU each, ctx 131072, Qwen3.8-27B UD-Q4_K_XL + mmproj-BF16 + MTP draft, launched via `start-server.sh` (quant selector Q4/Q6/Q8 → gguf globs in `/mnt/models`). `amd-gpu-profile.service` pins COMPUTE/HIGH perf state at boot, ordered before the servers. ROCm 10.0 + Vulkan builds of llama.cpp (master, unpinned).

### Logs

- llama-server logs — **local only** (14-day logrotate on the LLM VM). Shipping to OpenSearch `llm-logs-*` (former `modules/llm/observability.yml` Fluent Bit shipper) was removed 2026-09-08 as useless; `modules/llm/ansible.yml` now purges the old shipper on existing VMs. The ELK-side `llm-logs` ingest pipeline / index template / ISM policy are still deployed (harmless dead config; existing indices age out under the 14-day policy). The `llm-observability` dashboard was re-pointed 2026-09-08 to the body indices (`llm-request-body-*` / `llm-response-body-*`) and no longer references `llm-logs-*` (the two per-instance `llm-logs-*` panels on the `request-flow-llm` dashboard still do — dead until that dashboard is updated or the indices age out)
- nginx access (JSON `json_analytics` format) → Fluent Bit (nginx VM) → `nginx-access-*` (14d ISM)
- LLM request/response bodies — the lua capture on the llm vhost parses each JSON POST into two structured documents: the request doc embeds the decoded OpenAI payload as a queryable object (`request_body.messages[].role`/`content`, `tools[].function.name`/`parameters`, content part-arrays joined to text) with top-level `model`/`stream`/`messages_count`/`system_prompt`/`user_message` summaries, the response doc embeds the decoded payload as a queryable object (`response_body.choices[0].message.content`/`reasoning_content`/`tool_calls`; an SSE stream is reconstructed into the `chat.completion` shape with its deltas accumulated) with top-level completion id/model/usage/finish_reason and concatenated `content`/`reasoning_content` summaries, and both carry the full `json_analytics` identification fields (host, time_local, remote_addr, remote_user, request, status, body_bytes_sent, request_time, referrer, user-agent, XFF, upstream_addr/response_time/status, request_id) → `llm-request-body-YYYY.MM.dd` / `llm-response-body-YYYY.MM.dd` (90d ISM). The raw `nginx-body-*` capture was replaced 2026-09-08 (its indices age out under the 14d policy)
- OpenSearch ingest pipeline `llama-logs` groks 9 slot-line shapes + painless classifier + ~25 convert processors (with `_simulate` sanity assertion)
- ISM retention: 14d on access/body indices (matching 14-day logrotate on the LLM VM and Fluent Bit rotated-file exclusion), 90d on `llm-request-body-*` / `llm-response-body-*`
- Fluent Bit replaced Filebeat because Beats ≥7.13's unconditional `GET /_license` probe breaks against OpenSearch
- Five saved-object dashboards imported into Dashboards: `llm-observability` (re-pointed 2026-09-08 to the body indices), `nginx-proxy-analytics`, `request-flow-llm`, and — new 2026-09-09 — `llm-body-metrics` (14 charts: totals, latency/percentiles, token usage, finish_reason split, error counts, body sizes, context/tool/max-token distributions) and `llm-body-traces` (7 charts: per-request_id tables of slowest calls and upstream errors, request/response rate by instance, latency by instance, proxy overhead, max_tokens by model). Definitions live in `modules/elk/dashboards/llm-body-*-dashboard.json` / `-charts.json` and `llm-body-logs.json`, generated to `llm-body-observability.ndjson` by `generate_ods_objects.py` (all 21 charts verified live against ES before import)
- LLM body log browsing: a Discover saved search `llm-body-discover` over the `llm-*-body-*` pattern (columns request_id, model, upstream_status/addr, request_time, finish_reason, usage_total_tokens, messages_count). Logs Explorer saved searches do **not** work in this build: the Logs Explorer frontend saves/loads ES-side `savedQuery` objects (`.opensearch-observability`, via `/api/observability/event_analytics/saved_objects`) that it expects to carry `data_sources` (JSON string) + `query_lang`, but the `opensearch-observability` plugin's object schema strips both on create **and** on read — verified 2026-09-09 at three layers (Dashboards route 400 "definition for this key is missing", ES-side create strips, raw index doc has the fields while the object API returns them dropped) — so any saved search throws `SyntaxError: "undefined" is not valid JSON` on reopen (probes created/deleted). Discover is the log browser. The Dashboards **Observability** suite is otherwise unused: the *Applications* page (`/app/observability-applications`) is a trace-analytics feature — its views filter APM fields (`serviceName`, `traceGroup`) and derive the availability gauge from an attached operational panel — and applications are ES-side objects managed via `/api/observability/application/` (not importable saved objects: `unsupported_type`), so with no trace data in the body indices it stays empty by design (probe create/list/delete verified 2026-09-09; two orphaned panels from an earlier UI attempt were removed). PPL is available at `POST /_plugins/_ppl` (e.g. `source = llm-request-body-*,llm-response-body-* | head 5`), verified against the body indices

### Metrics

- node_exporter 1.12.1 on all 9 app VMs (as `nobody`, :9100)
- `gpu-metrics.py` on LLM VM (15 s systemd timer, amdgpu sysfs → textfile)
- `unbound-metrics.py` on dns VM (15 s timer, `unbound-control` unix socket)
- postgres_exporter 0.20.1 (:9187), Jenkins prometheus plugin (:8080/prometheus/)
- blackbox probes from monitoring VM: open-webui:8080, elk:9200+5601, nginx:80, taiga:8080 (front/static — was 9000, a dead port, fixed 2026-09-09), plus UDP dns probe of dnsmasq :53
- Prometheus 3.14 (30 d retention) → Grafana with 3 dashboards; native `grafana-opensearch-datasource` plugin (stock elasticsearch datasource returns empty frames against OpenSearch)

## 3. Deployment — two parallel paths

1. **Terraform:** `terraform apply` creates/updates VMs, then runs each module's playbook via `action "ansible_playbook_run"` (`on_failure = halt`). Ordering: every module `depends_on` dns; taiga additionally depends on postgres.
2. **Makefile:** `deploy-all` runs the same playbooks in a fixed order (dns → elk → postgres → taiga → llm → jenkins → jenkins-agent → open-webui → nginx → monitoring), pulling values from `proxmox.tfvars` via a `tfvar` grep function. `deploy-exporters` loops 9 hosts running `exporters.yml` per host (not part of `deploy-all` in the current working tree).

Playbooks double as the **update mechanism** — notably taiga: re-clone pinned tags (back 6.10.2 / protected 6.10.1 / events 6.10.0 / front-dist 6.10.3), reinstall deps, restart all 5 services on every run.

**Cloud-init immutability trap:** PVE can't update seed ISOs — any `cloud-init.yaml` edit forces full VM recreation. The jenkins module even documents "change hostname in the playbook," yet the playbook still sets the hostname (harmless redundancy, elk too).

## 4. Secrets handling

- 9 passwords/tokens in gitignored `proxmox.tfvars`; declared in root `variables.tf` **without `sensitive = true`**.
- Delivery: `--extra-vars` on the Ansible command line (visible in `ps` while a play runs) — via both paths.
- On-host:
  - Taiga generates `TAIGA_SECRET_KEY` / `RABBITMQ_PASS` once into `/opt/taiga/.env` (0600, `no_log`); rotation = delete file + re-run
  - Jenkins admin password in a **0644** groovy file plus 0600 JCasC
  - Agent SSH private key inlined in `jenkins.yaml` (0600) **and** copied to the controller at `/var/lib/jenkins/.ssh/`
  - `postgres_exporter.env` 0640 with plaintext DSN
  - LLM VM bakes `HF_TOKEN` into `/etc/environment` (playbook greps it back)
- Postgres is `scram-sha-256` over the LAN but Taiga connects with `POSTGRES_SSLMODE=disable`.

## 5. Issues found (priority order)

### Actually broken

1. ~~**Jenkins metrics job is permanently 401**~~ — **FIXED 2026-09-09**: `basic_auth` (admin / `jenkins_admin_password`) added to the jenkins scrape job; the password is wired through the monitoring module (variable → action extra_vars → playbook → prometheus config) and the Makefile `deploy-monitoring` target.
2. ~~**Taiga blackbox probe targets a dead port**~~ — **FIXED 2026-09-09**: probe target changed from `taiga:9000` to `taiga:8080` (front/static server, the same port nginx proxies to).
3. ~~**Taiga gunicorn `--worker-tmp-dir /dev/shm`**~~ — **FIXED 2026-09-09**: changed to `{{ taiga_root }}/.gunicorn-back` and `{{ taiga_root }}/.gunicorn-protected` (durable, under the deployment root — immune to both the per-user /dev/shm reap and /tmp boot-clearing). A playbook task creates the directories before the units start. The live VM had already been patched to use /tmp (crash-looped because the dir didn't exist); fixed in place and the playbook now uses the durable path.
4. ~~**`make deploy-jenkins` leaves `adminAddress` empty**~~ — **FIXED 2026-09-09**: Makefile now passes `jenkins_admin_email` via `--extra-vars` (matching the TF action path).
5. **`open-webui` receives `llm_ip` but never uses it** — the URL is hard-coded to `https://app.llm.lan/v1` (fine functionally, dead variable).

### Security posture

Consistently "trusted LAN," documented in headers, but worth enumerating:

- Dashboards :5601 is the only 0.0.0.0 bind with **zero** auth; OpenSearch :9200 binds LAN-IP-only, no auth
- Prometheus/blackbox 0.0.0.0, no auth, run as root
- Open WebUI allows self-registration (unauthenticated at the app hop)
- Jenkins agent uses `nonVerifyingKeyVerificationStrategy`; `jenkins` user is in the docker group (root-equivalent — controller compromise = root on agent VM)
- Nothing below the nginx `.lan` vhosts is TLS
- Secrets on the command line / in world-readable files (section 4)

### Staleness / dead code

- `claude-images.tf` downloads a Fedora 44 image that **no module consumes** — and every module call carries a meaningless `depends_on` on it
- Root `ansible.cfg` points at a nonexistent `inventory.ini`; all per-module `ansible.cfg` files are dead (Makefile always runs from repo root; taiga module has none at all)
- Filebeat still named in comments in `elk/ansible.yml` (4×), `elk/main.tf`, `nginx/main.tf`, `nginx/ansible.yml:679`, Makefile (2×) — the shipper is Fluent Bit
- ES-era DNS records `kibana.lan` / `elasticsearch.lan` / `app.kibana.lan` / `app.elastic.lan` survive in `dns/ansible.yml:33-41`
- `dns/main.tf` says router DHCP DNS → `.210` in one comment, `.220` in the next
- `postgres/database.yaml:35` still calls Taiga a "docker stack"
- `vllm.yml`: header says Ubuntu 24.04 (VMs are 26.04); `torchaudio 2.11.0` vs `torch 2.12.0` version skew; wheels from the rolling `whl-next` index; `ROCM_HOME=/opt/rocm` though ROCm lives in the venv. Install-only (no units, no log shipping), outside `deploy-all` — an experimental alternative backend to llama.cpp
- `exporters.yml:17-19` uses `lookup('env', ...)` with a stale "terraform passes via local-exec environment" comment — nothing does; the Makefile passes `--extra-vars` and the env lookups are dead fallbacks (silent empty-password path if run manually)
- `Makefile`: help comment says `make deploy` (only `deploy-all` exists)
- `start-server.sh` `usage()` text has the wrong argument order/defaults and a "Temperatore" typo; `SPLIT_MODE` is documented but hard-coded
- `hashicorp/local` provider (used for `data "local_file"` SSH keys) is undeclared in `versions.tf`; `os_ssd_slow` variable unused
- Taiga `.env` is first-run-only — changed `postgres_ip`/password stays stale until the file is deleted; `TAIGA_SITES_SCHEME=http` while clients are on https (server-generated links will say http)
- open-webui comment still says "port 8001" though traffic goes through the nginx pool

### Reproducibility gaps

- llama.cpp built from unpinned `master`
- OpenSearch 2.x apt (no version pin, currently 2.19.6) while the Grafana datasource hard-codes `version: 2.19.0`
- open-webui `uv pip install open-webui` unpinned
- uv itself via `curl | sh` (open-webui, taiga); Taiga re-downloads uv tarball + front-dist zip on every run and restarts all 5 services unconditionally

### Operational footguns

- Adding a VM requires three in-sync edits: prometheus `nodes` list, `exporters.yml` hosts, Makefile loop
- The monitoring VM itself has no node_exporter (its own CPU/RAM/disk unmonitored)
- The `dashboards/` dir double-ships the two Python collector scripts (copied into `/var/lib/grafana/dashboards/` where they're ignored)
- `ls /etc/postgresql` version detection in exporters.yml breaks if two majors coexist

## 6. Assessment

The architecture is coherent and the playbooks are unusually well-commented — incident context and *why* decisions (Fluent Bit over Filebeat, sysv DSM, OpenSearch datasource plugin, AppArmor workaround for Unbound) are documented at the point of use, and 14-day retention is consistent across ISM, logrotate, and Fluent Bit. The weak spots concentrate in: the `/dev/shm` class of bug recurring on Taiga (fixed 2026-09-09), secrets on the command line / in world-readable files, and a drift of ES/Kibana-era naming after the OpenSearch migration. Items 1–4 were fixed 2026-09-09; item 5 is cosmetic.
