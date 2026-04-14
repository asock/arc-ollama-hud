# arc-ollama-hud

> Real-time Intel Arc / xe GPU monitor and LLM throughput benchmark harness for [Ollama](https://ollama.com).

Pure Bash. No `intel_gpu_top`. No Python. Works on `xe` and `i915` drivers via sysfs.

---

## Tools

| Command | What it does |
|---------|-------------|
| `hud`   | Live TUI dashboard: GPU busy, VRAM, freq, power, temp + Ollama API/model status |
| `bench` | Token-throughput benchmark: runs N inference requests, samples GPU in parallel, outputs CSV + Markdown report |

---

## Requirements

| Dependency | Notes |
|-----------|-------|
| `bash ≥ 4.3` | Ships on every modern Linux |
| `curl` | Ollama API calls |
| `jq` | JSON parsing |
| `awk` | Stats aggregation |
| `ps`  | Process listing (hud) |
| Intel Arc GPU | `xe` or `i915` kernel driver; `/sys/class/drm/card*` must be accessible |
| [Ollama](https://ollama.com) | ≥ 0.3.0 recommended; `/api/tags`, `/api/ps`, `/api/generate` used |

---

## Install

```bash
git clone https://github.com/YOUR_USERNAME/arc-ollama-hud
cd arc-ollama-hud
./install.sh          # symlinks to ~/.local/bin (pass a path to override)
```

Or run directly without installing:

```bash
./bin/hud
./bin/bench -h
```

---

## hud

```
hud [INTERVAL_SECONDS]
```

| Env var | Default | Description |
|---------|---------|-------------|
| `OLLAMA_HOST` | `http://127.0.0.1:11434` | Ollama API endpoint |
| `GPU_CARD` | auto-detected | Force a specific card, e.g. `card1` |
| `STATE_DIR` | `$XDG_RUNTIME_DIR/arc-ollama-hud` | History file directory |
| `NO_COLOR` | unset | Set to any value to disable ANSI colours |

**Examples**

```bash
hud               # 1-second refresh
hud 0.5           # 500 ms refresh
GPU_CARD=card1 hud
OLLAMA_HOST=http://192.168.1.10:11434 hud
NO_COLOR=1 hud > /tmp/hud.log &
```

**What to watch**

- `GPU busy` + `Power` should spike during generation.
- If `VRAM trend` is flat while a model is active → CPU fallback. Check `OLLAMA_GPU_OVERHEAD` or your driver.
- `Freq` dropping under load → thermal throttle or power limit hit.

---

## bench

```
bench [OPTIONS]
```

| Flag | Env | Default | Description |
|------|-----|---------|-------------|
| `-m MODEL` | `OLLAMA_MODEL` | first installed | Model name |
| `-p TEXT`  | `OLLAMA_PROMPT` | built-in prompt | Prompt string |
| `-P FILE`  | — | — | Read prompt from file |
| `-r N`     | `RUNS` | `5` | Number of benchmark runs |
| `-s MS`    | `SAMPLE_MS` | `200` | GPU sample interval (ms) |
| `-o DIR`   | `OUT_DIR` | `./bench-out` | Output directory |
| `-H HOST`  | `OLLAMA_HOST` | `http://127.0.0.1:11434` | Ollama endpoint |
| `-c CARD`  | `GPU_CARD` | auto | Force GPU card |
| `-w`       | — | off | Add a warm-up run (discarded from stats) |
| `-q`       | — | off | Quiet mode (no per-run output) |

**Examples**

```bash
bench                                   # 5 runs, auto model, default prompt
bench -m qwen3:8b -r 10 -w             # 10 runs + warm-up, qwen3:8b
bench -m llama3.1:8b -p "Write a haiku about VRAM." -r 3
bench -P my_prompt.txt -r 5 -s 100     # 100 ms GPU samples
bench -q -r 20 -o ./results            # quiet, 20 runs, custom output dir
```

**Output files** (all in `OUT_DIR`):

| File | Contents |
|------|----------|
| `summary_TIMESTAMP.csv` | One row per run: throughput + aggregated GPU stats |
| `samples_TIMESTAMP.csv` | Time-series GPU samples (one row per sample interval) |
| `report_TIMESTAMP.md` | Human-readable Markdown summary table |
| `request_TIMESTAMP.json` | Exact request payload sent to Ollama |
| `resp_runN_TIMESTAMP.json` | Raw Ollama response JSON for each run |

**Reading the numbers**

- **eval tok/s** = `eval_count / eval_duration` (generation phase only, best throughput indicator)
- **total tok/s** = `eval_count / total_duration` (includes prompt processing and load time)
- Low eval tok/s + low GPU busy → CPU fallback or VRAM spill
- High power + low freq → thermal throttle (check `temp_max_c`)
- High `load_s` on first run → model cold load; use `-w` for warm benchmarks

---

## sysfs paths used

```
/sys/class/drm/cardN/device/
  gpu_busy_percent
  mem_info_vram_{used,total}
  mem_info_local_memory_{used,total}     # xe driver alias
  tile0/gt0/freq0/{cur,act}_freq         # xe
  gt/gt0/freq0/{cur,act}_freq            # i915
  hwmon/*/power1_average                 # µW → W
  hwmon/*/temp1_input                    # m°C → °C
  vendor  device  driver (symlink)
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `No Intel DRM card detected` | Wrong card index | `ls /sys/class/drm/` and set `GPU_CARD=cardN` |
| All GPU fields show `?` or blank | Permission denied on sysfs | Run as user with DRM access, or add `udev` rule |
| GPU busy always 0 during generation | CPU fallback | Check `ollama ps`; ensure `OLLAMA_GPU_OVERHEAD` allows GPU offload |
| `jq: command not found` | Missing dep | `sudo pacman -S jq` / `sudo apt install jq` |
| Ollama shows `down` | Not running or wrong host | `systemctl start ollama` or set `OLLAMA_HOST` |
| `bench` hangs | Slow model / timeout | Generation timeout is 300 s; try a smaller model |

---

## Architecture

```
arc-ollama-hud/
├── bin/
│   ├── hud          Live TUI monitor
│   └── bench        Benchmark harness
├── lib/
│   └── common.sh    Shared helpers (GPU discovery, unit converters, UI widgets)
├── install.sh       Symlink installer
└── .github/
    └── workflows/
        ├── lint.yml   ShellCheck CI
        └── test.yml   Smoke tests
```

All logic lives in `lib/common.sh`. Both tools `source` it — zero duplication.

---

## Contributing

1. Fork + branch
2. `shellcheck bin/* lib/*`
3. Test on real hardware if possible; otherwise mock sysfs with tmpfs
4. PR with a brief description of what changed and why

---

## License

MIT – see [LICENSE](LICENSE).
