# Hardcoded Domain Names — Audit Report

Date: 2026-09-25 · Tree: `main` @ clean (audit performed on committed state)

Full-repo inventory of private-domain literals. This repo has no `packages/`
directory; scope is the root files plus everything under `modules/`.

## 1. Current state

The intended convention is that every private FQDN derives from a single
source of truth — a root `local.lan_names` map (names) and `var.lan_domain`
(domain suffix, default `"lan"`) — and that no module ever writes a literal
name or netplan domain. **That mechanism is not present in this tree**:
`git log --all -S lan_names` is empty, only `main` exists, and neither
`local.lan_names` nor `variable "lan_domain"` is defined anywhere. Every
name below is therefore hardcoded.

## 2. Method

- FQDN pattern: `[a-zA-Z0-9_-]+(\.[a-zA-Z0-9_-]+)*\.lan` over the whole repo
  (excluding `.git`, `.terraform`, `.state`, `.idea`).
- Netplan domain literals: `domain\s*[:=]\s*["']?lan`.
- Non-`.lan` private names: `\.(local|box)` scan.
- Raw matches were de-duplicated per token and per file, then each surviving
  hit was classified: functional (config rendered to a VM) vs. comment/doc,
  or false positive (variable reference / loop variable).

## 3. Functional hardcoded names

### 3.1 `modules/dns/ansible.yml` — 43 occurrences

The dnsmasq static record list (the canonical name set of the LAN):

| Lines | Records |
|-------|---------|
| 21–34 | `pve.lan`, `dns.lan`, `llm.lan`, `jenkins.lan`, `jenkins-agent.lan`, `open-webui.lan`, `postgres.lan`, `taiga.lan`, `monitoring.lan`, `grafana.lan`, `prometheus.lan`, `elk.lan`, `kibana.lan`, `elasticsearch.lan` |
| 37–60 | `nginx.lan`, `app.kibana.lan`, `app.elk.lan`, `app.elastic.lan`, `app.grafana.lan`, `app.prometheus.lan`, `app.jenkins.lan`, `app.open-webui.lan`, `app.langflow.lan`, `ui-agent.llm.lan`, `code-swarm-agent.llm.lan`, `code-smith-agent.llm.lan`, `stt.llm.lan`, `stt-de.llm.lan`, `tts.llm.lan`, `tts-de-martin.llm.lan`, `tts-de-victoria.llm.lan`, `embed.llm.lan`, `deepseek.llm.lan`, `app.taiga.lan`, `git.lan`, `app.git.lan`, `qdrant.lan`, `app.qdrant.lan` |

Plus the post-deploy verify task: `postgres.lan` at lines 335, 342, 369.

Non-`.lan` private name: **`w8s.local`** (line 255, FritzBox router
forward) — the one name intentionally left hardcoded.

### 3.2 `modules/nginx/ansible.yml` — 65 occurrences

- Local CA subject: `-subj "/CN=app.lan"` (line 138).
- vhost list, lines 79–99 — 21 names (the `app.*.lan` / `*.llm.lan` set from
  3.1 minus the bare service names).
- `server_name` directives:

  | Line | vhost |
  |------|-------|
  | 193 | `app.kibana.lan app.elk.lan` |
  | 212 | `app.elastic.lan` |
  | 227 | `app.grafana.lan` |
  | 246 | `app.prometheus.lan` |
  | 261 | `app.jenkins.lan` |
  | 281 | `app.open-webui.lan` |
  | 306 | `app.langflow.lan` |
  | 335 | `app.qdrant.lan` |
  | 354 | `app.git.lan` |
  | 380 | `app.taiga.lan` |
  | 459 | `ui-agent.llm.lan` |
  | 508 | `code-swarm-agent.llm.lan` |
  | 537 | `code-smith-agent.llm.lan` |
  | 571 | `stt.llm.lan` |
  | 597 | `stt-de.llm.lan` |
  | 618 | `tts.llm.lan` |
  | 642 | `tts-de-martin.llm.lan` |
  | 662 | `tts-de-victoria.llm.lan` |
  | 687 | `embed.llm.lan` |
  | 715 | `deepseek.llm.lan` |

- Post-deploy verify tasks: `app.kibana.lan` (1202), `app.qdrant.lan` (1220),
  `ui-agent.llm.lan` (1238), `deepseek.llm.lan` (1256, 1261),
  `app.taiga.lan` (1272, 1275).

### 3.3 `modules/langflow/`

- `ansible.yml`: `code-swarm-agent.llm.lan` (50), `deepseek.llm.lan` (52),
  `embed.llm.lan` (53), `app.qdrant.lan` (56),
  `LANGFLOW_SSRF_ALLOWED_HOSTS` with 7 names (413), TLS pre-flight loop with
  3 names (520).
- `main.tf:109` — **Terraform output URL**: `https://app.langflow.lan`.

### 3.4 `modules/open-webui/ansible.yml`

`ui-agent.llm.lan` (20), `embed.llm.lan` (27), `app.qdrant.lan` (32),
`stt.llm.lan` (43), `stt-de.llm.lan` (44), `tts.llm.lan` (323).

### 3.5 `modules/taiga/ansible.yml`

`app.taiga.lan` as the api/events URL (150, 151), `TAIGA_SITES_DOMAIN` (370),
and as the email domain in `taiga@app.taiga.lan` (386) and
`admin@app.taiga.lan` (679).

### 3.6 `modules/git/ansible.yml`

Gitea env: `DOMAIN = app.git.lan` (97), `ROOT_URL = https://app.git.lan/`
(98), `SSH_DOMAIN = git.lan` (101).

### 3.7 Netplan search domain — all 13 module `main.tf`

Every VM's netplan hardcodes the domain suffix instead of taking it from a
variable:

`git:37`, `dns:45`, `elk:53`, `jenkins-agent:35`, `open-webui:37`,
`qdrant:37`, `monitoring:44`, `langflow:37`, `taiga:37`, `nginx:44`,
`jenkins:42`, `postgres:37`, `llm:40` — all reading
`domain = "lan"` in their `initialization` block.

## 4. Dashboards (`modules/elk/dashboards/`)

- **Functional Lucene queries** (filter on the access-log `host` field):
  `nginx-charts.json:50,65` and `nginx-dashboards.ndjson:6,7` —
  `host.keyword:ui-agent.llm.lan OR host.keyword:code-swarm-agent.llm.lan OR
  host.keyword:code-smith-agent.llm.lan`.
- **Description prose only**: `llm-dashboard.json:4`,
  `llm-dashboards.ndjson:8`, `llm-body-metrics-dashboard.json:4`,
  `llm-body-traces-dashboard.json:4`, `llm-body-observability.ndjson:18,26`,
  `nginx-charts.json:47` (agent vhost names in dashboard descriptions).

## 5. Docs and comments (non-functional)

- `README.md`: 39, 62 (the `DOMAINS=` SAN list, 11 names), 75
  (`CN=app.lan`), 122, 187, 200, 201, 205.
- `REPORT.md`: 18, 28–32, 87, 105. Note line 29 documents `app.webui.lan`,
  but the live nginx vhost is `app.open-webui.lan` — the report is stale.
- `Makefile`: target comments at 76, 87, 96, 168.
- Module header comments: `modules/nginx/main.tf:3`,
  `modules/dns/main.tf:11–12`, `modules/langflow/variables.tf:41`,
  `modules/qdrant/ansible.yml:6`, plus in-playbook comments at
  `nginx/ansible.yml:3–14,707,1087` (line 1087 mentions the retired
  `app.llm.lan` round-robin vhost), `langflow/ansible.yml:6,43–45,55,421`,
  `open-webui/ansible.yml:22,36,367`, `taiga/ansible.yml:16`,
  `git/ansible.yml:4`.

## 6. Complete unique name inventory

**41 `.lan` FQDNs:**

`pve.lan` · `dns.lan` · `llm.lan` · `jenkins.lan` · `jenkins-agent.lan` ·
`open-webui.lan` · `postgres.lan` · `taiga.lan` · `monitoring.lan` ·
`grafana.lan` · `prometheus.lan` · `elk.lan` · `kibana.lan` ·
`elasticsearch.lan` · `nginx.lan` · `git.lan` · `qdrant.lan` ·
`app.kibana.lan` · `app.elk.lan` · `app.elastic.lan` · `app.grafana.lan` ·
`app.prometheus.lan` · `app.jenkins.lan` · `app.open-webui.lan` ·
`app.langflow.lan` · `app.taiga.lan` · `app.git.lan` · `app.qdrant.lan` ·
`app.llm.lan` (retired, docs/comments only) · `app.webui.lan` (stale,
REPORT.md only) · `app.lan` (CA subject CN) · `ui-agent.llm.lan` ·
`code-swarm-agent.llm.lan` · `code-smith-agent.llm.lan` · `stt.llm.lan` ·
`stt-de.llm.lan` · `tts.llm.lan` · `tts-de-martin.llm.lan` ·
`tts-de-victoria.llm.lan` · `embed.llm.lan` · `deepseek.llm.lan`

**Plus 1 non-`.lan` private name:** `w8s.local` (FritzBox).

## 7. False positives (checked, not domains)

- `modules/llm/ansible.yml` (4 hits) — `{{ item.lang }}` language codes
  (en/de), not hostnames.
- Root `main.tf` (37 hits) — `var.lan_network`, `var.lan_gateway`,
  `var.lan_ip`, `var.lan_ca_token`, `var.langflow_*` variable references.
- `docs.langflow.org` in the langflow playbooks — external upstream doc URL.
- `proxmox_virtual_environment_file.langflow_config` — Terraform resource
  reference.

## 8. Totals

| Category | Files | Occurrences |
|----------|-------|-------------|
| dns playbook (records + verify) | 1 | 43 |
| nginx playbook | 1 | 65 |
| langflow (ansible + tf output) | 2 | 16 |
| open-webui playbook | 1 | 9 |
| taiga playbook | 1 | 6 |
| git playbook | 1 | 4 |
| qdrant playbook (comment) | 1 | 1 |
| netplan `domain = "lan"` | 13 | 13 |
| ELK dashboards | 7 | 11 |
| docs/comments (README, REPORT, Makefile, headers) | 6 | ~25 |
| **Total** | **~30 files** | **~195** |

## 9. Next step

Re-apply the parameterization: root `local.lan_names` map (single source of
truth) + `var.lan_domain`, forwarded to the six name-consuming modules
(dns, nginx, git, open-webui, taiga, langflow) as `lan_names` (JSON-encoded
extra var, parsed in-play as `names`) and `lan_domain`. The netplan domain
literal is dropped from all 13 `initialization` blocks per the earlier
decision that a domain rename must never touch VM resources. After the
change, a pure domain rename produces zero Terraform diff; the six
name-consuming playbooks are re-run manually via their `make deploy-*`
targets.
