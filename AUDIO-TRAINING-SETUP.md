# Custom German TTS Voice — Kokoro Fine-Tune & Deploy Plan

> **Status: PLAN ONLY (2026-09-28).** No VM or repo changes have been made yet.
>
> **Voice name: TBD.** Every `<name>` placeholder below becomes the chosen short
> name (e.g. `fritz`). Conventions, mirroring the existing voices:
>
> | Artifact            | Pattern (existing examples)          | New voice                          |
> |---------------------|--------------------------------------|------------------------------------|
> | Voice ID / file     | `dm_martin`, `dv_victoria`           | `d<initial>_<name>.pt`             |
> | FQDN                | `tts-de-martin.llm.lan`, `tts-de-victoria.llm.lan` | `tts-de-<name>.llm.lan` |
> | systemd unit        | `kokoro-de-martin.service`           | `kokoro-de-<name>.service`         |
> | Service port (LLM VM) | 8087 (martin), 8088 (victoria)     | **8090**                           |

---

## 1. Goal

Record the user's own voice, fine-tune **Kokoro-82M** (the same architecture as
the already-running German voices) on that recording, and deploy the result as a
third German Kokoro-FastAPI instance behind the existing
nginx → `.lan` → Open WebUI stack — so the user can simply switch the TTS
endpoint in Open WebUI to get their own voice, with no new VMs, no new
services, and no architectural changes.

## 2. Why this approach

Compared on 2026-09-28 (voice cloning vs. fine-tuning):

| Route | Verdict |
|-------|---------|
| **Kokoro-82M fine-tune (chosen)** | Stays 100% inside the existing architecture: Kokoro-FastAPI, OpenAI-compatible `/v1/audio/speech`, nginx vhost, `.lan` DNS, Open WebUI OpenAI-TTS settings. No license caveats (MIT). Single-GPU trainable. |
| XTTS v2 | Great clone quality from ~6 s, but separate inference stack (TortoiseTTS), heavier VRAM footprint, and its license restricts commercial use. |
| GPT-SoVITS | Needs ~1 min of clean speech + reference clips per request; different serving stack, more moving parts. |

The actual pipeline behind kikiri's German voices (Martin, Victoria) is
public and reproducible: **`semidark/kikiri-tts`** (GitHub). semidark is a
member of the `kikiri-tts` HuggingFace org and the recipe is linked from the
`kikiri-german-*` model cards. It is a StyleTTS2-based fine-tune of Kokoro-82M.

Key facts (verified 2026-09-28):

- **Only Stage 2 (single-speaker fine-tune) is needed.** Stage 1
  (building a new-language base model) is skipped: we start from the public
  multi-speaker German base
  **`kikiri-tts/kikiri-german-base-51speakers-synthetic`** on HuggingFace.
- **Data budget is small.** Victoria used **455 clips**, Martin **627 clips**,
  both trained **10 epochs**. Target: **400–600 clips × 2–30 s ≈ 1–1.5 h** of
  clean German audio.
- **Best results come from reading a prepared script** (exact transcripts,
  no whisper guesswork) — we will generate a phonetically balanced German
  passage list (~500 passages) before recording.

## 3. Existing voice stack (context, unchanged)

```
Open WebUI (192.168.51.204)
   │  TTS: https://tts-de-<voice>.llm.lan/v1   (UI-stored, overrides env)
   ▼
nginx VM 202 (192.168.51.208)   vhost per .lan name, LAN CA TLS, no buffering
   ▼
LLM VM (192.168.51.201, user `llm`, 4× AMD RDNA4 R9700 32 GB)
   ├─ kokoro        :8086  (English, base model)
   ├─ kokoro-de-martin   :8087
   ├─ kokoro-de-victoria :8088
   ├─ whisper-server     :8085 (STT en)
   └─ whisper-server-de  :8089 (STT de)
   All Kokoro units: shared venv, HIP_VISIBLE_DEVICES=3 (kokoro_gpu var)
```

DNS: `modules/dns/ansible.yml` maps `tts-de-*.llm.lan` → `{{ nginx_ip }}`.
The new voice follows the exact same path on port 8090.

**No Terraform changes are needed**: no new VM, no new exposed ports — the
LLM VM is already on the LAN and the nginx VM already reaches it directly.

## 4. Data requirements (the only part that needs the user)

| Property        | Value |
|-----------------|-------|
| Total duration  | **1–1.5 h** clean German |
| Clips           | **400–600**, each **2–30 s** |
| Language        | German only, natural speaking pace |
| Content         | Read from the **prepared script** (generated, exact transcripts) |
| Format on disk  | WAV, **mono, 24 kHz, 16-bit** |
| No              | music, reverb, compression, EQ, second speakers, background noise |

Recording details are in Phase 2.

---

## Phase 1 — Training environment on the LLM VM

One-time setup, ~30–60 min. All under `/home/llm/kikiri-tts`, user `llm`.
Training runs **single-GPU on card 1 or 2** (each ~11 GB VRAM free; card 3 is
nearly full and keeps the serving stack).

```bash
ssh -i ~/.ssh/proxmox-ubuntu llm@192.168.51.201

# 1. System packages (German G2P + audio I/O)
sudo apt-get update && sudo apt-get install -y espeak-ng libsndfile1

# 2. Recipe repo (submodules: patched kokoro/ + StyleTTS2/)
cd /home/llm
git clone --recurse-submodules https://github.com/semidark/kikiri-tts
cd kikiri-tts
uv sync                       # main venv, Python 3.12 (G2P, dataset scripts, Kokoro)
```

The StyleTTS2 trainer gets a **separate venv** (it must not be mixed with the
kokoro-fastapi runtime venvs):

```bash
# 3. Trainer venv
uv venv .venv-sts2 --python 3.12
uv pip install --python .venv-sts2/bin/python \
  torch torchaudio accelerate transformers librosa soundfile \
  pyyaml tensorboard munch phonemizer huggingface_hub Cython

# 4. Build the monotonic_align C extension the trainer imports
#    (Cython build inside the StyleTTS2/ checkout — see repo README)

# 5. espeakng-loader data symlink fix
#    (StyleTTS2's espeakng-loader expects the espeak-ng data dir at a fixed
#     path; Ubuntu needs the symlink described in the README)
```

Then the model pieces (all downloaded on the VM, never on the mac):

```bash
# 6. StyleTTS2 utility models (wavlm etc.) -> the checkpoints dir the
#    trainer expects (see README)

# 7. German base model (Stage-1 output of the kikiri pipeline, public)
uv run huggingface-cli download kikiri-tts/kikiri-german-base-51speakers-synthetic \
  --local-dir base-model/

# 8. Convert base weights to the trainer's checkpoint layout
#    (conversion snippet from the repo README — one small python script)
```

**Sanity check before recording anything** (the German symbol table must be
intact; wrong G2P data is the #1 silent-quality killer):

```bash
uv run python - <<'EOF'
# per README: load the German symbol map and assert
#   len(symbols) == 178
#   dicts['ç'] == 78
#   dicts['ʦ'] == 20
#   dicts['ː'] == 158
print("symbol map OK")
EOF
```

**2-step smoke test** (proves ROCm + trainer work before committing to an
overnight run — use a throwaway 10-clip mini dataset, or the one the README
ships with):

```bash
cd /home/llm/kikiri-tts/StyleTTS2
# accelerate config: LOCAL_MACHINE, distributed type NO,
#                    mixed_precision: no, num_processes: 1
HIP_VISIBLE_DEVICES=1 accelerate launch train_second.py \
  --config_path ../configs/config_german_ft.yml
# Ctrl-C after 2 steps. Success = finite, in-range losses printed;
# compare the first-step loss values with the ranges in the README.
```

> **Go/no-go gate:** if the smoke test prints finite losses, the training
> stack is good. If MIOpen hangs on the *first* run for 10–30 min, that is
> **expected** (kernel compilation; cached in `~/.cache/miopen` afterwards) —
> don't kill it.

## Phase 2 — Recording (user, ~1 evening in a quiet room)

Deliverable from me: **`dataset/script.txt`** — ~500 German passages,
1–2 sentences each (3–25 words), generated phonetically balanced:

- full German phoneme coverage incl. `ä ö ü ß` and the `ch` variants
  (ich/ach/uch), word-final devoicing, `ei/ie`, `eu/äu`
- declarative, interrogative, exclamative mix
- numbers (spelled out), decimals, common punctuation (`. , ; : ! ?`)
- no proper names of public figures, no anything that should not be
  synthesised later (it becomes TTS training data — only use neutral content)

Recording procedure:

1. Quiet room (closet full of clothes works), fan/AC off, phone off.
2. Mic at fixed 15–20 cm distance; note the exact setup and don't change it.
3. Record in your normal speaking voice — consistent volume and pace across
   the whole session (consistency matters more than perfection).
4. Read one passage per file, 300–500 ms silence before/after. Misreads are
   fine as long as they are *natural*; re-record only stutters/cross-talk.
5. Keep 10–20 of your **best, most natural clips** separately — they become
   the voicepack reference set (Phase 5).
6. File names in script order: `0001.wav`, `0002.wav`, … (keep the mapping
   to `script.txt` exact — it is the transcript source).

Normalise to the required format (on the mac or the VM):

```bash
# per file
ffmpeg -y -i raw/0001.wav -ac 1 -ar 24000 -sample_fmt s16 clean/0001.wav
# or batch
for f in raw/*.wav; do
  ffmpeg -y -i "$f" -ac 1 -ar 24000 -sample_fmt s16 "clean/$(basename "$f")"
done
```

Transfer to the VM and verify:

```bash
scp -i ~/.ssh/proxmox-ubuntu -r clean/* llm@192.168.51.201:/home/llm/kikiri-tts/dataset/clean/
scp -i ~/.ssh/proxmox-ubuntu dataset/script.txt llm@192.168.51.201:/home/llm/kikiri-tts/dataset/

# on the VM — spot-check a few files
ffprobe -v error -show_entries stream=sample_rate,channels,codec_name \
  -of csv /home/llm/kikiri-tts/dataset/clean/0001.wav
# expect: 24000, 1, pcm_s16le
```

Listen to ~10 random clips end-to-end; delete/replace bad ones (clicks,
breath-heavy starts, clipping) before continuing.

## Phase 3 — Dataset preparation

On the VM, inside `/home/llm/kikiri-tts` (exact flags per repo README):

```bash
# 1. Transcripts: one line per clip, in file order (from the prepared script).
#    dataset/transcripts.txt:
#      line for 0001.wav
#      line for 0002.wav
#      ...

# 2. G2P: text -> IPA using misaki's espeak G2P (German), with the ʏ→y fix
#    the recipe requires:
#      g2p  = misaki.espeak.EspeakG2P(language="de")
#      ipa  = g2p(text).replace("ʏ", "y")

# 3. Build the training list. Required line format:
#      /abs/path/to/0001.wav|<IPA phoneme string>|<speaker_name>
#    (<speaker_name> = anything consistent, e.g. "<name>"; single-speaker)
uv run python scripts/prepare_dataset.py ...        # per README

# 4. Split/normalise into the trainer input (train/val split happens here)
uv run python scripts/prepare_training.py ...       # per README
```

Verify before training: clip count ≈ recorded count, every line has exactly
two `|` separators, IPA strings are non-empty and contain no `ʏ`.

## Phase 4 — Stage-2 fine-tuning (10 epochs, overnight)

Config: the repo's `configs/config_german_ft.yml`. The keys that matter for a
German Stage-2 run (the rest are the recipe defaults):

```yaml
batch_size: 4                # ROCm: fp32, small batches
save_freq: 1                 # one checkpoint per epoch
pretrained_model: <path to converted German base model>   # Phase 1 step 8
load_only_params: true
# Stage-2 block:
second_stage_load_pretrained: false
joint_epoch: 3
lambda_slm: 1.0
```

Launch (from `StyleTTS2/`, **fp32 only, single process**):

```bash
cd /home/llm/kikiri-tts/StyleTTS2
# accelerate config (already done in Phase 1):
#   LOCAL_MACHINE, distributed type NO, mixed_precision: no, num_processes: 1
HIP_VISIBLE_DEVICES=1 accelerate launch train_second.py \
  --config_path ../configs/config_german_ft.yml
```

Expectations:

- **~500 clips / batch 4 ≈ 125 steps/epoch.** Reference pace on a
  single-GPU AMD card: order of minutes per epoch; plan **8–24 h for 10
  epochs** → start overnight.
- Checkpoints: `epoch_2nd_00000.pth … epoch_2nd_00009.pth` in the run's log
  dir. Disk: a few GB for all checkpoints (82M fp32 ≈ 0.33 GB each) — the
  LLM VM has headroom.
- Monitor: loss table in the log (SLM/STS losses), optionally tensorboard.
  Healthy = steady decline, no NaN.
- If it dies on restart, just relaunch the same command (trainer resumes
  from config; pick the last complete checkpoint).

## Phase 5 — Voicepack extraction & evaluation

The fine-tuned `.pth` is the *model*; Open WebUI/Kokoro-FastAPI additionally
needs a 512-dim style-embedding **voicepack** `.pt` built from reference
clips of the target voice.

```bash
cd /home/llm/kikiri-tts

# 1. Voicepack from the 10–20 best reference clips (Phase 2 step 5)
uv run python scripts/extract_voicepack.py \
  --model  StyleTTS2/logs/<run>/epoch_2nd_00009.pth \
  --audio-dir dataset/voicepack/ \
  --output voices/<name>.pt

# 2. Inference test: synthesize a fixed set of German test sentences
uv run python scripts/test_inference.py \
  --checkpoint StyleTTS2/logs/<run>/epoch_2nd_00009.pth \
  --voicepack  voices/<name>.pt \
  --output-dir test_output/
```

**Evaluation (the human gate):** generate the same test sentences for 2–3
candidate epochs (e.g. `00007`, `00008`, `00009`) and listen for:

1. **Similarity** to the user's real voice (the whole point).
2. **German phoneme accuracy** — no anglicised vowels, clean `ä/ö/ü/ß/ch`.
3. **Prosody** — natural intonation, not monotone or robotic.
4. **Artifacts** — no cracks, warble, or click bursts.

Pick the best epoch (kikiri ships `ep10` for both public voices — 10 epochs
is the proven default). Then stage the final artifacts to a stable location
independent of the training tree:

```bash
mkdir -p /home/llm/voices-custom/<name>
cp StyleTTS2/logs/<run>/epoch_2nd_000NN.pth /home/llm/voices-custom/<name>/kokoro-v1_0.pth
cp voices/<name>.pt                          /home/llm/voices-custom/<name>/<voice_id>.pt
```

> Optional alternative: upload both files to a **private** HuggingFace repo
> and let the existing HF-download playbook tasks fetch them. Default plan is
> **local staging only** — your voice stays on the homelab.

## Phase 6 — Deploy as a Kokoro instance (repo changes)

Four small, pattern-following module edits (no Terraform, no new VM):

### 6.1 `modules/llm/ansible.yml`

a) Instance list (line ~37) — add the new speaker:

```yaml
    kokoro_de_instances:
      - { name: martin,   port: 8087, model_repo: kikiri-tts/kikiri-german-martin,   model_file: kikiri_german_martin_ep10.pth,   voice: dm_martin,   voice_src: voices/martin.pt }
      - { name: victoria, port: 8088, model_repo: kikiri-tts/kikiri-german-victoria, model_file: kikiri_german_victoria_ep10.pth, voice: dv_victoria, voice_src: voices/victoria.pt }
      - { name: <name>,   port: 8090, voice: d<initial>_<name>, local: true }
```

b) The two `get_url` tasks (German models / voicepacks, line ~980–1013) must
be skipped for the local instance — add `when: not item.local | default(false)`
to each. (config.json download and directory creation already loop over the
list, so they apply automatically.)

c) New task staging the locally-trained artifacts into the per-speaker tree
the units expect (after the voice-directory creation task):

```yaml
    - name: Stage the custom-voice model and voicepack (trained on this VM)
      ansible.builtin.copy:
        src: "{{ item.src }}"
        dest: "{{ item.dest }}"
        remote_src: true
        owner: llm
        group: llm
        mode: "0644"
      loop:
        - { src: "/home/llm/voices-custom/<name>/kokoro-v1_0.pth",
            dest: "{{ kokoro_de_dir }}/models-<name>/v1_0/kokoro-v1_0.pth" }
        - { src: "/home/llm/voices-custom/<name>/<voice_id>.pt",
            dest: "{{ kokoro_de_dir }}/voices-<name>/d<initial>_<name>.pt" }
```

d) Port wait (line ~1127): `[8085, 8086, 8087, 8088, 8089]` → add `8090`.
The TTS probe loop, unit templating, daemon reload and enable/start all
already loop over `kokoro_de_instances` — the new unit
`kokoro-de-<name>.service` comes for free.

e) Handlers: add the matching restart handler (line ~1166 ff.):

```yaml
    - name: restart kokoro-de-<name>
      ansible.builtin.systemd:
        name: kokoro-de-<name>
        state: restarted
```

f) GPU placement: the unit template uses `HIP_VISIBLE_DEVICES={{ kokoro_gpu }}`
(card 3). An 82M instance adds ~2–4 GB VRAM. Card 3 is the tightest
(whisper + 3 Kokoro already there) — if `rocm-smi` shows < ~4 GB free after
the new unit starts, either move `kokoro_gpu` or add a per-instance key:

```yaml
Environment=HIP_VISIBLE_DEVICES={{ item.gpu | default(kokoro_gpu) }}
```

and `gpu: "2"` on the new instance entry.

### 6.2 `modules/dns/ansible.yml`

After line 54:

```yaml
      - "address=/tts-de-<name>.llm.lan/{{ nginx_ip }}"
```

### 6.3 `modules/nginx/ansible.yml`

1. `lan_https_domains` list (line ~95): add `- tts-de-<name>.llm.lan`
   (the module regenerates the cert SAN from this list on deploy).
2. New vhost variable, cloned from `tts_de_victoria_vhost` (line ~693):

   ```yaml
   tts_de_<name>_vhost: |
     server {
         listen 443 ssl;
         server_name tts-de-<name>.llm.lan;

         location / {
             proxy_pass http://{{ llm_ip }}:8090;
             proxy_http_version 1.1;
             proxy_set_header Host $host;
             proxy_set_header X-Real-IP $remote_addr;
             proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
             proxy_set_header X-Forwarded-Proto $scheme;
             add_header Strict-Transport-Security "max-age=31536000" always;
             # Kokoro can stream audio; don't buffer it
             proxy_buffering off;
             proxy_read_timeout 300s;
             proxy_send_timeout 300s;
         }
     }
   ```
3. vhost file list (line ~1082):
   `- { file: "tts-de-<name>-llm.conf", content: "{{ tts_de_<name>_vhost }}" }`
4. managed-conf list (line ~1112): `- tts-de-<name>-llm.conf`

### 6.4 `modules/open-webui/ansible.yml`

No mandatory change. The TTS base URL is **UI-stored** (webui.db `config`,
key `audio.tts.openai.api_base_url`) and overrides the env default
(`AUDIO_TTS_OPENAI_API_BASE_URL`, line ~323) — switching voices happens in
the UI (Phase 7). Optionally update the env default later if the new voice
becomes the primary German one.

### 6.5 Deploy

```bash
# from the repo root — dependency order: LLM backend, DNS, then nginx gateway
make deploy-llm
make deploy-dns
make deploy-nginx
```

`deploy-llm` ends with its built-in end-to-end probe: it synthesizes a
German sentence on port 8090 with voice `d<initial>_<name>` and requires
HTTP 200 — the deployment is proven at the service level before touching
the gateway.

## Phase 7 — Open WebUI wiring & end-to-end verification

1. **Service level (already done by the playbook probe).**
2. **Gateway level:**

   ```bash
   curl -sS --cacert <lan-ca.pem> \
     -X POST https://tts-de-<name>.llm.lan/v1/audio/speech \
     -H 'Content-Type: application/json' \
     -d '{"model":"kokoro","input":"Hallo, das ist meine eigene Stimme.","voice":"d<initial>_<name>","lang_code":"d","response_format":"mp3"}' \
     -o /tmp/myvoice.mp3
   # 200 + a playable mp3 in your voice = TLS SAN, vhost, proxy all good
   ```

3. **Open WebUI (UI → Settings → Audio → Text-to-speech):**
   - TTS engine: `openai`
   - Base URL: `https://tts-de-<name>.llm.lan/v1`
   - Voice: `d<initial>_<name>`
   - STT stays as is: `https://stt-de.llm.lan/v1` (large-v3-turbo, German)
4. **Round trip:** talk a German sentence into Open WebUI → STT de → LLM
   answer → TTS in your voice. (The same TTS→STT-de round-trip check the
   playbook runs for Victoria is the model for what to expect.)

---

## 8. Hardware & ROCm notes (LLM VM)

- **Single-GPU only.** The VM (i440FX, PCIe atomics unavailable) cannot run
  RCCL/NCCL collectives — any multi-GPU training attempt dies with
  `hipErrorIllegalState`. Fine-tuning an 82M model is a single-GPU job
  anyway.
- **fp32 only.** fp16/bf16 mixed precision on RDNA4 → silent MIOpen crashes
  or hangs (documented on the 8060S). `accelerate config` must say
  `mixed_precision: no`.
- **batch_size ≤ 4** for stable ROCm behaviour at this model size.
- **First run compiles MIOpen kernels** (+10–30 min of no output — do not
  kill). Cache lives in `~/.cache/miopen`; later runs start instantly.
- **Card choice:** train on card **1 or 2** (~11 GB free each; 82M fp32
  batch 4 fits comfortably). Serve on card 3 with the rest of the stack
  (or card 2 if card 3 runs tight — see 6.1f).
- Disk budget: dataset < 0.5 GB, checkpoints ~5 GB, venvs ~10 GB. All fine.

## 9. Gotchas & troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| First training minutes: no output, GPU busy | MIOpen kernel compilation — expected, wait it out |
| MIOpen crash / hang mid-training | mixed precision accidentally enabled → `accelerate config` → `no` |
| Garbage/robotic German | G2P: `ʏ→y` fix missing, or symbol-map asserts failed in Phase 1 |
| Voice sounds like a *different* person | voicepack built from poor reference clips → rebuild from the 10–20 best clips |
| Overfit (same intonation on every sentence, slight warble) | try an earlier epoch (00007/00008) |
| `InvalidUrlClientError` in Open WebUI | UI-stored base URL typo (e.g. one slash) — the Victoria incident of 2026-09-28; the UI value overrides the env var |
| Cert errors on the new FQDN | `lan_https_domains` entry missing → `make deploy-nginx` regenerates SANs |
| Probe fails but `curl 127.0.0.1:8090` works | vhost/SAN/dns layer — check `tts-de-<name>.llm.lan` resolves to `192.168.51.208` and `nginx -t` |

## 10. Open questions (need user decisions)

1. **Voice name** — drives `tts-de-<name>.llm.lan`, the `d<initial>_<name>`
   voice ID, and all unit/file names. (Only blocking decision for Phases 1–6
   naming; training itself can start before the name is final.)
2. Model hosting: **local staging only** (plan default) vs. private HF repo.
3. Serve on card 3 (convention) vs. card 2 (VRAM headroom) — decide after
   checking `rocm-smi` in Phase 6.

## 11. Status & next steps

| Phase | Description | Status |
|-------|-------------|--------|
| 0 | Plan + recipe verification | ✅ done (2026-09-28) |
| 1 | Training env + smoke test on LLM VM (go/no-go) | ⏳ pending — say "start phase 1" |
| 2 | Generate German recording script (~500 passages) + user records 1–1.5 h | ⏳ pending |
| 3 | Dataset prep (G2P, list, split) | ⏳ pending |
| 4 | Stage-2 fine-tune, 10 epochs (overnight) | ⏳ pending |
| 5 | Voicepack + epoch evaluation (user picks) | ⏳ pending |
| 6 | Repo module edits + `make deploy-llm/dns/nginx` | ⏳ pending |
| 7 | Open WebUI switch + end-to-end verification | ⏳ pending |
