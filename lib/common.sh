#!/usr/bin/env bash
# lib/common.sh – shared helpers for arc-ollama-hud tools

# ── Colour palette (degraded gracefully when NO_COLOR is set) ────────────────
_setup_colors() {
  if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    C_RESET='\033[0m' C_DIM='\033[2m' C_BOLD='\033[1m'
    C_RED='\033[31m'  C_GREEN='\033[32m' C_YELLOW='\033[33m'
    C_BLUE='\033[34m' C_MAG='\033[35m'   C_CYAN='\033[36m' C_GRAY='\033[90m'
  else
    C_RESET='' C_DIM='' C_BOLD='' C_RED='' C_GREEN='' C_YELLOW=''
    C_BLUE='' C_MAG='' C_CYAN='' C_GRAY=''
  fi
}
_setup_colors

# ── GPU discovery ─────────────────────────────────────────────────────────────
# Returns the sysfs path for the first Intel DRM card found.
# Honours $GPU_CARD env var (e.g. "card1") to select a specific card.
gpu_find_card() {
  local hint="${GPU_CARD:-}"
  if [[ -n "$hint" && -d "/sys/class/drm/$hint/device" ]]; then
    echo "/sys/class/drm/$hint"; return 0
  fi
  local d vendor
  for d in /sys/class/drm/card[0-9]*; do
    [[ -d "$d/device" ]] || continue
    vendor="$(<"$d/device/vendor" 2>/dev/null)" || continue
    [[ "${vendor,,}" == "0x8086" ]] && { echo "$d"; return 0; }
  done
  return 1
}

# Read the first readable file from a list; print empty string on failure.
gpu_read() {
  local f
  for f in "$@"; do [[ -r "$f" ]] && { cat "$f"; return 0; }; done
  printf ''
}

# Try all known freq sysfs paths for Intel i915/xe drivers
gpu_freq_paths() {
  local dev="$1"
  echo \
    "$dev/tile0/gt0/freq0/cur_freq" \
    "$dev/gt/gt0/freq0/cur_freq" \
    "$dev/tile0/gt0/freq0/act_freq" \
    "$dev/gt/gt0/freq0/act_freq"
}

# ── Unit converters ───────────────────────────────────────────────────────────
bytes_to_mib()  { [[ "$1" =~ ^[0-9]+$ ]] && awk -v b="$1" 'BEGIN{printf "%.1f",b/1048576}' || echo ''; }
uw_to_w()       { [[ "$1" =~ ^[0-9]+$ ]] && awk -v u="$1" 'BEGIN{printf "%.2f",u/1000000}'  || echo ''; }
mc_to_c()       { [[ "$1" =~ ^[0-9]+$ ]] && awk -v m="$1" 'BEGIN{printf "%.1f",m/1000}'     || echo ''; }
ns_to_s()       { [[ "$1" =~ ^[0-9]+$ ]] && awk -v n="$1" 'BEGIN{printf "%.3f",n/1e9}'      || echo ''; }
safe_int()      { [[ "$1" =~ ^[0-9]+$ ]] && echo "$1" || echo 0; }
safe_num()      { [[ "$1" =~ ^[0-9]+(\.[0-9]+)?$ ]] && echo "$1" || echo 0; }
div_fmt()       { awk -v a="${1:-0}" -v b="${2:-0}" 'BEGIN{if(b>0) printf "%.2f",a/b; else print ""}'; }

# ── GPU stats struct (populates associative array) ────────────────────────────
# Usage: gpu_read_stats DEV  (sets GPU_BUSY GPU_USED_RAW GPU_TOTAL_RAW
#        GPU_FREQ GPU_POWER_W GPU_TEMP_C GPU_MEM_PCT GPU_USED_MIB GPU_TOTAL_MIB)
gpu_read_stats() {
  local dev="$1"
  GPU_BUSY="$(safe_int "$(gpu_read "$dev/gpu_busy_percent")")"
  GPU_USED_RAW="$(gpu_read "$dev/mem_info_vram_used" "$dev/mem_info_local_memory_used")"
  GPU_TOTAL_RAW="$(gpu_read "$dev/mem_info_vram_total" "$dev/mem_info_local_memory_total")"
  # shellcheck disable=SC2046
  GPU_FREQ="$(gpu_read $(gpu_freq_paths "$dev"))"
  # S2: Guard the hwmon globs — if $dev is empty the glob expands from /
  #     which is unintended and wastes a filesystem traversal.
  local pwr_raw='' temp_raw=''
  if [[ -n "$dev" ]]; then
    pwr_raw="$(gpu_read "$dev"/hwmon/*/power1_average)"
    temp_raw="$(gpu_read "$dev"/hwmon/*/temp1_input)"
  fi
  GPU_POWER_W="$(uw_to_w "$pwr_raw")"
  GPU_TEMP_C="$(mc_to_c "$temp_raw")"
  GPU_USED_MIB="$(bytes_to_mib "$GPU_USED_RAW")"
  GPU_TOTAL_MIB="$(bytes_to_mib "$GPU_TOTAL_RAW")"
  GPU_MEM_PCT=0
  if [[ "$GPU_USED_RAW" =~ ^[0-9]+$ && "$GPU_TOTAL_RAW" =~ ^[0-9]+$ && "$GPU_TOTAL_RAW" -gt 0 ]]; then
    GPU_MEM_PCT=$(awk -v u="$GPU_USED_RAW" -v t="$GPU_TOTAL_RAW" 'BEGIN{printf "%d",(u/t)*100}')
  fi
}

# ── Terminal UI helpers ───────────────────────────────────────────────────────
SPARKLINE_CHARS=(▁ ▂ ▃ ▄ ▅ ▆ ▇ █)

ui_hr() {
  printf "%b%s%b\n" "$C_GRAY" \
    "──────────────────────────────────────────────────────────────────────────────" \
    "$C_RESET"
}

ui_kv() {
  printf "%b%-18s%b %s\n" "$C_CYAN" "$1" "$C_RESET" "$2"
}

ui_panel() {
  printf "\n%b▌ %s%b\n" "$C_BOLD$C_MAG" "$1" "$C_RESET"
}

# Coloured progress bar  usage: ui_bar VALUE [WIDTH]
ui_bar() {
  local val="${1:-0}" width="${2:-26}" fill empty color
  (( val < 0   )) && val=0
  (( val > 100 )) && val=100
  fill=$(( val * width / 100 ))
  empty=$(( width - fill ))
  if   (( val < 40 )); then color="$C_GREEN"
  elif (( val < 75 )); then color="$C_YELLOW"
  else                      color="$C_RED"
  fi
  printf "%b[" "$color"
  # shellcheck disable=SC2046
  printf '█%.0s' $(seq 1 "$fill"  2>/dev/null)
  printf "%b" "$C_GRAY"
  # shellcheck disable=SC2046
  printf '░%.0s' $(seq 1 "$empty" 2>/dev/null)
  printf "%b] %3s%%%b" "$color" "$val" "$C_RESET"
}

# Sparkline from a history file  usage: ui_spark HISTFILE [MAX]
# U4: Sparkline width adapts to terminal width (half the terminal, 20–60 chars)
ui_spark() {
  local file="$1" max="${2:-100}" out='' idx v
  [[ -f "$file" ]] || { echo '─'; return; }
  local cols; cols="$(tput cols 2>/dev/null || echo 80)"
  local spark_width=$(( cols / 2 ))
  (( spark_width < 20 )) && spark_width=20
  (( spark_width > 60 )) && spark_width=60
  while IFS= read -r v; do
    v="$(safe_num "$v")"
    idx=$(awk -v n="$v" -v m="$max" 'BEGIN{if(m<=0)m=1;i=int((n/m)*7);if(i<0)i=0;if(i>7)i=7;print i}')
    out+="${SPARKLINE_CHARS[$idx]}"
  done < <(tail -n "$spark_width" "$file" 2>/dev/null)
  echo "$out"
}

# Append value to rolling history file (keeps last N lines)
hist_append() {
  local file="$1" val="$2" max="${3:-240}"
  echo "$val" >> "$file"
  local lines; lines=$(wc -l < "$file" 2>/dev/null)
  if (( lines > max )); then
    tail -n "$max" "$file" > "$file.tmp" && mv "$file.tmp" "$file"
  fi
}

# ── Dependency checks ─────────────────────────────────────────────────────────
require_cmds() {
  local missing=()
  for cmd in "$@"; do command -v "$cmd" &>/dev/null || missing+=("$cmd"); done
  if (( ${#missing[@]} > 0 )); then
    printf '%bMissing required commands: %s%b\n' "$C_RED" "${missing[*]}" "$C_RESET" >&2
    return 1
  fi
}
