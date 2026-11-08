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

- llama-server logs — **local only** (14-day logrotate on the LLM VM). Shipping to OpenSearch `llm-logs-*` 
- nginx access (JSON `json_analytics` format) → Fluent Bit (nginx VM) → `nginx-access-*` (14d ISM)
- LLM request/response bodies
- ISM retention: 14d on `nginx-access-*` (matching 14-day logrotate on the LLM VM and Fluent Bit rotated-file exclusion), 90d on `llm-request-body-*` / `llm-response-body-*`
- Fluent Bit replaced Filebeat because Beats ≥7.13's unconditional `GET /_license` probe breaks against OpenSearch
- Five saved-object dashboards imported into Dashboards
- LLM body log browsing

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

- tokens delivered via `proxmox.tfvars`; declared in root `variables.tf`
- Delivery: `--extra-vars` on the Ansible command line (visible in `ps` while a play runs) — via both paths.

