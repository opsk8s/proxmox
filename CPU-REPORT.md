# VM CPU / vCPU Allocation Report

**Date:** 2026-10-22
**Scope:** All 13 VMs managed by this Terraform repo, cross-checked against the live PVE host.

## 1. Host

| | |
|---|---|
| CPU | AMD Ryzen Threadripper PRO 3975WX — **32 cores / 64 threads** (SMT on), 1 socket |
| Source | `lscpu` on 192.168.51.200 (queried live, 2026-10-22) |

## 2. Per-VM allocation

Values are from root `variables.tf` defaults (no sizing overrides in `proxmox.tfvars`) and
verified against both the Terraform state (`.state/terraform.tfstate`) and live
`qm config` on the host — all three sources agree.

| VM ID | Name            | vCPU (sockets × cores) | CPU type | cpulimit / cpuunits / affinity | RAM (dedicated) |
|-------|-----------------|------------------------|----------|--------------------------------|-----------------|
| 100   | llm-ubuntu      | **8** (1 × 8)          | host     | none                           | 32 GB           |
| 101   | jenkins-server  | 2 (1 × 2)              | qemu64   | none                           | 8 GB            |
| 102   | jenkins-agent   | 4 (1 × 4)              | qemu64   | none                           | 8 GB            |
| 103   | open-webui      | 2 (1 × 2)              | host     | none                           | 8 GB            |
| 104   | postgres        | **8** (1 × 8)          | qemu64   | none                           | 16 GB           |
| 105   | taiga           | 2 (1 × 2)              | qemu64   | none                           | 4 GB            |
| 106   | git             | 1 (1 × 1)              | host     | none                           | 2 GB            |
| 107   | qdrant          | 2 (1 × 2)              | host     | none                           | 4 GB            |
| 108   | langflow        | 2 (1 × 2)              | host     | none                           | 4 GB            |
| 200   | monitoring      | 2 (1 × 2)              | qemu64   | none                           | 4 GB            |
| 201   | elk             | 2 (1 × 2)              | qemu64   | none                           | 6 GB            |
| 202   | nginx           | 4 (1 × 4)              | qemu64   | none                           | 4 GB            |
| 220   | dns             | 1 (1 × 1)              | qemu64   | none                           | 2 GB            |

## 3. Totals

| Metric | Value |
|---|---|
| **Total vCPUs dedicated to VMs** | **40** |
| Physical cores (host) | 32 |
| Hardware threads (host) | 64 |
| Overcommit vs physical cores | 40 / 32 = **1.25×** (if every VM demanded 100 % CPU simultaneously) |
| Fraction of hardware threads | 40 / 64 = **62.5 %** |
| VMs using `cpu: host` | 5 (llm, open-webui, git, qdrant, langflow) — host CPU feature passthrough for numpy/torch wheels |
| VMs using `cpu: qemu64` (default) | 8 |

## 4. Observations

1. **No hard pinning anywhere.** No `cpulimit`, `cpuunits`, or core affinity is set on any
   VM — all 40 vCPUs float freely across all 64 threads. The `// N physical` comments in the
   module files (e.g. `modules/postgres/main.tf`, `modules/nginx/main.tf`) are sizing *intent*
   notes only; nothing enforces a vCPU→physical-core mapping.
2. **Some comments are stale.** `modules/llm/main.tf` line 1 and `modules/elk/main.tf`
   line 8 still assume a **12-core** host ("the host is fully allocated (12 cores …)"); the
   current host has 32 cores / 64 threads. Also `modules/postgres/main.tf` says
   `// 4 physical` while allocating 8 vCPU, and `modules/nginx/main.tf` says
   `// 2 physical` while allocating 4 — the comments predate the size bumps in
   `variables.tf` (postgres 8, nginx 4).
3. **Headroom exists.** 40 vCPUs on 64 threads is not oversubscribed in the usual homelab
   sense: even a full 100 % draw across all VMs leaves ~⅓ of the threads, though only 32
   physical cores exist (SMT gives at most 64 concurrent streams). The heaviest consumers —
   llm (8) and postgres (8) — together are 40 % of all allocated vCPUs.
4. **Drift check passed.** Terraform state == live host config for all 13 VMs; no manual
   `qm set` changes outside IaC.

## 5. Method

- `variables.tf` defaults (source of truth for sizing; `proxmox.tfvars` carries no `*_cpu_cores` overrides)
- `.state/terraform.tfstate` → `cpu.cores`/`sockets` per `proxmox_virtual_environment_vm`
- Live host: `ssh proxmox 'lscpu'` and `qm config <id>` for every VM ID from `qm list`
