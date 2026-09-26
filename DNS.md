# Hardcoded Domain Names — Audit Report

Date: 2026-09-26 · Tree: `main` @ `7722488` (clean, audit performed on committed state)

Full-repo inventory of private-domain literals. This repo has no `packages/`
directory; scope is the root files plus everything under `modules/`.

## 1. Current state

The intended convention is that every private FQDN derives from a single
source of truth — a root `local.lan_names` map (names) and `var.lan_domain`
(domain suffix, default `"lan"`) — and that no module ever writes a literal
name or netplan domain. **That mechanism is not present in this tree**:
neither `local.lan_names` nor `variable "lan_domain"` is defined in any
`.tf` or `.yml` file (the only hits for the strings are this report's own
prose). Every name below is therefore hardcoded.

## 2. Method

- FQDN pattern: `[a-zA-Z0-9_-]+(\.[a-zA-Z0-9_-]+)*\.lan` over the whole repo
  (excluding `.git`, `.terraform`, `.state`, `.idea`).
- Netplan domain literals: `domain\s*[:=]\s*["']?lan`.
- Non-`.lan` private names: `\.(local|box)` scan.
- Counting convention: a name is counted once per distinct line in a
  distinct file (a token repeated twice on one line counts once), then each
  hit is classified: functional (config rendered to a VM) vs. comment/doc,
  or false positive (variable reference / loop variable).
- This report (`DNS.md`) is now tracked in the repo: its own ~141
  self-references are excluded from every count below.

## 3. Functional hardcoded names

### 3.1 `modules/dns/ansible.yml` — 43 occurrences

The dnsmasq static record list (the canonical name set of the LAN):

| Lines | Records |
|-------|---------|
| 21–34 | `pve.lan`, `dns.lan`, `llm.lan`, `jenkins.lan`, `jenkins-agent.lan`, `open-webui.lan`, `postgres.lan`, `taiga.lan`, `monitoring.lan`, `grafana.lan`, `prometheus.lan`, `elk.lan`, `kibana.lan`, `elasticsearch.lan` |
| 37–61 | `nginx.lan`, `app.kibana.lan`, `app.elk.lan`, `app.elastic.lan`, `app.grafana.lan`, `app.prometheus.lan`, `app.jenkins.lan`, `app.open-webui.lan`, `app.langflow.lan`, `ui-agent.llm.lan`, `code-swarm-agent.llm.lan`, `code-smith-agent.llm.lan`, `code-assistent.llm.lan`, `stt.llm.lan`, `stt-de.llm.lan`, `tts.llm.lan`, `tts-de-martin.llm.lan`, `tts-de-victoria.llm.lan`, `embed.llm.lan`, `deepseek.llm.lan`, `app.taiga.lan`, `git.lan`, `app.git.lan`, `qdrant.lan`, `app.qdrant.lan` |

Plus the `nginx.lan` mention in the comment at line 35, and the post-deploy
verify task: `postgres.lan` at lines 336, 343, 370.

Non-`.lan` private name: **`w8s.local`** (line 256, FritzBox router
forward) — the one name intentionally left hardcoded.

### 3.2 `modules/nginx/ansible.yml` — 70 occurrences

- Header comment map, lines 3–15 — 11 `app.*.lan` names plus
  `ui-agent.llm.lan`, `code-swarm-agent.llm.lan`, `code-smith-agent.llm.lan`,
  `code-assistent.llm.lan` (line 13), `deepseek.llm.lan`, `app.taiga.lan`.
- `lan_https_domains` list (the cert SAN list), lines 80–101 — 22 names.
- Local CA subject: `-subj "/CN=app.lan"` (line 140).
- `server_name` directives:

  | Line | vhost |
  |------|-------|
  | 195 | `app.kibana.lan app.elk.lan` |
  | 214 | `app.elastic.lan` |
  | 229 | `app.grafana.lan` |
  | 248 | `app.prometheus.lan` |
  | 263 | `app.jenkins.lan` |
  | 283 | `app.open-webui.lan` |
  | 308 | `app.langflow.lan` |
  | 337 | `app.qdrant.lan` |
  | 356 | `app.git.lan` |
  | 382 | `app.taiga.lan` |
  | 461 | `ui-agent.llm.lan` |
  | 510 | `code-swarm-agent.llm.lan` |
  | 539 | `code-smith-agent.llm.lan` |
  | 568 | `code-assistent.llm.lan` |
  | 602 | `stt.llm.lan` |
  | 628 | `stt-de.llm.lan` |
  | 649 | `tts.llm.lan` |
  | 673 | `tts-de-martin.llm.lan` |
  | 693 | `tts-de-victoria.llm.lan` |
  | 718 | `embed.llm.lan` |
  | 738 | (comment: `host=deepseek.llm.lan`) |
  | 746 | `deepseek.llm.lan` |

- Retired-vhost comment: `app.llm.lan` at line 1120 (the old round-robin
  `app.llm.lan` proxy, replaced by the per-agent vhosts).
- Post-deploy verify tasks: `app.kibana.lan` (1231, 1235), `app.qdrant.lan`
  (1249, 1253), `ui-agent.llm.lan` (1271), `deepseek.llm.lan` (1289, 1294),
  `app.taiga.lan` (1305, 1308).

### 3.3 `modules/langflow/`

- `ansible.yml` — 21 functional: `ui-agent.llm.lan` (43),
  `code-smith-agent.llm.lan` (44), `deepseek.llm.lan` + `embed.llm.lan`
  (45), `code-swarm-agent.llm.lan` (50), `deepseek.llm.lan` (52),
  `embed.llm.lan` (53), `app.qdrant.lan` (55, 56), `embed.llm.lan` (421),
  `LANGFLOW_SSRF_ALLOWED_HOSTS` with 7 names (413: `ui-agent`,
  `code-swarm-agent`, `code-smith-agent`, `deepseek`, `embed`,
  `app.qdrant`, `app.elastic` — note `code-assistent` is **not** on this
  list), TLS pre-flight loop with 3 names (520: `code-swarm-agent`,
  `embed`, `app.qdrant`).
- `main.tf:109` — **Terraform output URL**: `https://app.langflow.lan`
  (line 72 repeats it in a comment).
- `variables.tf:41` — comment.

### 3.4 `modules/open-webui/ansible.yml` — 10 occurrences

`ui-agent.llm.lan` (20), `embed.llm.lan` (22, 27, 367), `stt.llm.lan`
(36, 43), `stt-de.llm.lan` (36, 44), `app.qdrant.lan` (32),
`tts.llm.lan` (323).

### 3.5 `modules/taiga/ansible.yml` — 6 occurrences

`app.taiga.lan` in the header comment (16), as the api/events URL
(150, 151), `TAIGA_SITES_DOMAIN` (370), and as the email domain in
`taiga@app.taiga.lan` (386) and `admin@app.taiga.lan` (679).

### 3.6 `modules/git/ansible.yml` — 4 occurrences

Gitea env: `DOMAIN = app.git.lan` (97), `ROOT_URL = https://app.git.lan/`
(98), `SSH_DOMAIN = git.lan` (101), plus the header comment (4).

### 3.7 Netplan search domain — all 13 module `main.tf`

Every VM's netplan hardcodes the domain suffix instead of taking it from a
variable:

`git:37`, `dns:45`, `elk:53`, `jenkins-agent:35`, `open-webui:37`,
`qdrant:37`, `monitoring:44`, `langflow:37`, `taiga:37`, `nginx:44`,
`jenkins:42`, `postgres:37`, `llm:40` — all reading
`domain = "lan"` in their `initialization` block.

## 4. Dashboards (`modules/elk/dashboards/`) — 19 occurrences

- **Functional Lucene queries** (filter on the access-log `host` field):
  `nginx-charts.json:50,65` and `nginx-dashboards.ndjson:6,7` —
  `host.keyword:ui-agent.llm.lan OR host.keyword:code-swarm-agent.llm.lan OR
  host.keyword:code-smith-agent.llm.lan`. **`code-assistent.llm.lan` is not
  in these filters**, so its traffic is invisible in the agent dashboards.
- **Description prose only**: `nginx-charts.json:47`,
  `llm-dashboard.json:4`, `llm-dashboards.ndjson:8`,
  `llm-body-metrics-dashboard.json:4`, `llm-body-traces-dashboard.json:4`,
  `llm-body-observability.ndjson:18,26`.

## 5. Docs and comments (non-functional)

- `README.md` — 18: `app.taiga.lan` (39, 187, 200, 201, 205), the
  `DOMAINS=` SAN list (62, 11 names), `CN=app.lan` (75),
  `ui-agent.llm.lan` (122).
- `REPORT.md` — 14: `app.llm.lan` (18, 31, 87), `jenkins.lan` (28),
  `app.webui.lan` (29), `taiga.lan` (30), `app.kibana.lan` +
  `app.elastic.lan` + `grafana.lan` + `prometheus.lan` (32),
  `app.kibana.lan` + `app.elastic.lan` + `kibana.lan` +
  `elasticsearch.lan` (105). Note line 29 documents `app.webui.lan`,
  but the live nginx vhost is `app.open-webui.lan` — the report is stale.
- `Makefile` — 4: target comments at 76, 87, 96, 168.
- Module header comments: `modules/nginx/main.tf:3` (`app.kibana.lan`,
  `app.grafana.lan`), `modules/dns/main.tf:11–12` (6 service names),
  `modules/qdrant/ansible.yml:6`.
- `DNS.md` (this file) is tracked in the repo; its ~141 self-references are
  excluded from all counts per the §2 convention.

## 6. Complete unique name inventory

**42 `.lan` FQDNs:**

`pve.lan` · `dns.lan` · `llm.lan` · `jenkins.lan` · `jenkins-agent.lan` ·
`open-webui.lan` · `postgres.lan` · `taiga.lan` · `monitoring.lan` ·
`grafana.lan` · `prometheus.lan` · `elk.lan` · `kibana.lan` ·
`elasticsearch.lan` · `nginx.lan` · `git.lan` · `qdrant.lan` ·
`app.kibana.lan` · `app.elk.lan` · `app.elastic.lan` · `app.grafana.lan` ·
`app.prometheus.lan` · `app.jenkins.lan` · `app.open-webui.lan` ·
`app.langflow.lan` · `app.taiga.lan` · `app.git.lan` · `app.qdrant.lan` ·
`app.llm.lan` (retired, docs/comments only) · `app.webui.lan` (stale,
REPORT.md only) · `app.lan` (CA subject CN) · `ui-agent.llm.lan` ·
`code-swarm-agent.llm.lan` · `code-smith-agent.llm.lan` ·
`code-assistent.llm.lan` · `stt.llm.lan` · `stt-de.llm.lan` ·
`tts.llm.lan` · `tts-de-martin.llm.lan` · `tts-de-victoria.llm.lan` ·
`embed.llm.lan` · `deepseek.llm.lan`

**Plus 1 non-`.lan` private name:** `w8s.local` (FritzBox).

## 7. False positives (checked, not domains)

- `modules/llm/ansible.yml` (4 hits: 785, 802, 810, 1081) —
  `{{ item.lang }}` language codes (en/de), not hostnames.
- Root `main.tf` (37 hits) and the module `main.tf` files —
  `var.lan_network`, `var.lan_gateway`, `var.lan_ip`, `var.lan_ca_token`,
  `var.langflow_*` variable references.
- `docs.langflow.org` in the langflow playbooks (12, 264) — external
  upstream doc URL.
- `proxmox_virtual_environment_file.langflow_config`
  (`modules/langflow/main.tf:41,78`) — Terraform resource reference.
- `app.lan` is **not** a false positive: it is the real local-CA subject CN,
  listed in §6.

## 8. Totals

| Category | Files | Occurrences |
|----------|-------|-------------|
| dns playbook (records + comment + verify) | 1 | 43 |
| nginx playbook (header, SAN list, vhosts, verify) | 1 | 70 |
| langflow (ansible + main.tf + variables.tf) | 3 | 36 |
| open-webui playbook | 1 | 10 |
| taiga playbook | 1 | 6 |
| git playbook | 1 | 4 |
| llm playbook (`item.lan` false positives) | 1 | 4 |
| qdrant playbook (comment) | 1 | 1 |
| netplan `domain = "lan"` | 13 | 13 |
| ELK dashboards | 7 | 19 |
| root `main.tf` (`var.lan_*` false positives) | 1 | 37 |
| module `main.tf` (var refs + header comments, excl. langflow) | 12 | 71 |
| docs/comments (README, REPORT, Makefile, headers) | 3 | 36 |
| **Total (excl. `DNS.md` self-references)** | **46** | **350** |

Plus 1 non-`.lan` private name (`w8s.local`) → **351**.

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
