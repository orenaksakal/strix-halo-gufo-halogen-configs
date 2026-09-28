# Gufo / Halogen service configurations for Strix Halo

These are the **tested runtime settings** from the September 28, 2026 comparison,
packaged as Docker Compose services. The measured runs used direct `docker run`.
The inference settings here match those runs; Compose adds service restart/log
rotation policy, uses the model alias `flash-next`, and publishes port 18080.

The tuning pass was small: Gufo MTP ceilings 4/7 and Halogen prefill arenas 4K/8K.
It selected MTP-4 and an 8K arena. This is a reproducible configuration, not a
claim of globally optimal tuning. Calibration preceded the final version update.

Upstream projects: [Gufo](https://github.com/gufo-org/gufo) ·
[Halogen](https://github.com/peonist-ai/halogen-flash-server) ·
[Strix Halo Toolboxes](https://github.com/kyuz0/amd-strix-halo-toolboxes).

## Hardware and engine settings

Framework Desktop, Ryzen AI Max+ 395 / Radeon 8060S, 128 GB shared RAM,
Ubuntu 26.04, 512 MiB firmware UMA carve-out.

| Setting | Gufo | Halogen |
|---|---|---|
| Version tested | `982bffea86fd5568759a420c4808c5b2123161c8`, ROCm 10 | `0.14.2` |
| Target weights | Same four `UD-Q4_K_XL` GGUF shards | Same four `UD-Q4_K_XL` GGUF shards |
| Total context per request | 126,000 tokens | 126,000 tokens |
| Concurrent sessions | 3 | 3 |
| Shared context pool | Engine-managed session state | 378,624 positions, shrinking disabled |
| Speculation | Adaptive MTP, ceiling 4 | Default MTP depth 2 and adaptive policy |
| Prefill tuning | Engine defaults | 8,192-token arena and chunk |
| Sampling defaults | Temperature 1.0, top-p 0.95, top-k 20 | Same |
| Thinking | On | On; automatic answer reserve disabled |
| Live prompt cache | On | On |
| Persistent prompt cache | Off in this comparison | Off in this comparison |

The engines require different compatible MTP heads. Halogen repacks the same
target GGUF in RAM; this configuration does not use Halogen's native checkpoint.
126K is **input + reasoning + answer**, not 126K input plus an output allowance.
Three configured sessions describes capacity; the final easy test was a single
request, not three simultaneously full contexts.

These were the latest upstream versions checked at **2026-09-28 02:24 UTC**.
The pinned references reproduce that point in time. The public Gufo `latest`
image was older, so Gufo was built from source.

## Files

- `compose.yaml`: both services, selectable by profile.
- `example.env`: local paths and numeric device-group IDs.
- `build-gufo.sh`: source- and recipe-pinned Gufo build.
- [`tuned/strix-halo-performance/tuned.conf`](tuned/strix-halo-performance/tuned.conf): the host's TuneD profile.

## Model directories

Set `MODELS_DIR` to this tree:

```text
Qwen3.8-Flash-Next-GGUF/
├── UD-Q4_K_XL/
│   ├── Qwen3.8-Flash-Next-UD-Q4_K_XL-00001-of-00004.gguf
│   ├── Qwen3.8-Flash-Next-UD-Q4_K_XL-00002-of-00004.gguf
│   ├── Qwen3.8-Flash-Next-UD-Q4_K_XL-00003-of-00004.gguf
│   └── Qwen3.8-Flash-Next-UD-Q4_K_XL-00004-of-00004.gguf
└── MTP/
    └── mtp-Qwen3.8-Flash-Next-shared-Q8_0.gguf
```

Source: [`unsloth/Qwen3.8-Flash-Next-GGUF`](https://huggingface.co/unsloth/Qwen3.8-Flash-Next-GGUF/tree/38bb39ee97821de2c9009abb7e93950eec396e66),
revision `38bb39ee97821de2c9009abb7e93950eec396e66`.

Set `HALOGEN_SUPPORT_DIR` to the directory containing
`qwen38-flash-next-mtp.hgn` and the complete `tokenizer/` directory from
[`peonist-ai/halogen-qwen3.8-flash-next`](https://huggingface.co/peonist-ai/halogen-qwen3.8-flash-next/tree/6bee31c0d22ce405b86f51aec741f08c0be923c8),
revision `6bee31c0d22ce405b86f51aec741f08c0be923c8`.

With the Hugging Face CLI installed, the corresponding downloads are:

```bash
hf download unsloth/Qwen3.8-Flash-Next-GGUF \
  --revision 38bb39ee97821de2c9009abb7e93950eec396e66 \
  --include 'UD-Q4_K_XL/*' 'MTP/mtp-Qwen3.8-Flash-Next-shared-Q8_0.gguf' \
  --local-dir /srv/models/Qwen3.8-Flash-Next-GGUF

hf download peonist-ai/halogen-qwen3.8-flash-next \
  --revision 6bee31c0d22ce405b86f51aec741f08c0be923c8 \
  --include 'qwen38-flash-next-mtp.hgn' 'tokenizer/*' \
  --local-dir /srv/models/halogen-flash-support
```

## Configure and run

Clone this repository, then set the paths and host group IDs:

```bash
git clone https://github.com/orenaksakal/strix-halo-gufo-halogen-configs.git
cd strix-halo-gufo-halogen-configs
cp example.env .env
# Edit .env: model directories, UID/GID, and device group IDs.
id -u
id -g
stat -c %g /dev/kfd
stat -c %g /dev/dri/renderD128

bash build-gufo.sh
docker compose --profile halogen pull
docker compose --profile gufo --profile halogen config --quiet

# Start Gufo:
docker compose --profile gufo up -d
curl --fail http://127.0.0.1:18080/ready

# Switch to Halogen, releasing Gufo's model memory first:
docker compose --profile gufo --profile halogen down
docker compose --profile halogen up -d
curl --fail http://127.0.0.1:18080/health
```

Select one engine at a time on this 128 GB host. Readiness succeeds once loading
finishes; `docker compose logs -f` shows startup. Both profiles use the same
loopback API port. Stop any existing model server before using these services.
Both GPU devices belong to group 990 on the tested host, so `group_add` lists
that GID once. If the two `stat` commands return different GIDs on your host,
add the second numeric GID as another `group_add` entry in `compose.yaml`.

## Exact measured request

The service defaults are not the complete benchmark configuration. The final easy
request explicitly set **low** reasoning effort and a 125,847-token maximum,
the remaining space after its 153-token prompt. Both engines ended naturally.
Gufo's service default was 126,000; Halogen's default was 32,768 with a 126,000
cap. The explicit request overrides both defaults. `HALOGEN_MAX_TOK=8192` sizes
prefill scratch; it is not a generation limit.

```bash
curl http://127.0.0.1:18080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "flash-next",
    "messages": [{"role": "user", "content": "Implement Python function merge_intervals(intervals). Input is a list of [start,end] closed integer intervals with start <= end. Return a new list sorted by start, merging overlapping OR touching intervals (e.g. [1,3] and [3,4] merge; [1,2] and [3,4] do not). Handle empty input, duplicates, negative endpoints, and zero-length intervals. Do not mutate the input. O(n log n) time. Return only the complete Python code in one python code block, using the standard library."}],
    "temperature": 1.0,
    "top_p": 0.95,
    "top_k": 20,
    "seed": 12345,
    "chat_template_kwargs": {"enable_thinking": true},
    "reasoning_effort": "low",
    "max_tokens": 125847,
    "stream": true,
    "stream_options": {"include_usage": true}
  }'
```

## Actual TuneD host profile

Both engines ran on the same host profile:

```ini
[main]
summary=Accelerator performance compatible with Secure Boot kernel lockdown
include=accelerator-performance

# Kernel lockdown denies the parent's scheduler debugfs reads/writes.
[scheduler]
enabled=0
```

CPU governors were `performance`. The host boot parameters included:

```text
amd_iommu=off amdgpu.gttsize=126976 ttm.pages_limit=32505856
```

These describe the measured host; they are not established prerequisites or a
universal tuning recipe. The shared 153-token benchmark does not measure bulk
prefill throughput or thermally steady-state behavior.

## Image identity

- Gufo source-built image observed locally:
  `sha256:ec61bb4be96f1dd94574d33c8878c0cfb7a59840ce8b21c5f0e248183ffe67f2`.
  This is a local image ID, not a public download. `build-gufo.sh` creates the tag
  used by Compose. Source and recipe are pinned; Fedora/ROCm package resolution
  at build time can produce a different image digest.
- Halogen public image:
  `ghcr.io/peonist-ai/halogen-flash-server@sha256:f3f99aa48f3a051f18da9ee24b333ca108fe745773fd036a365fe1875871d0be`.
