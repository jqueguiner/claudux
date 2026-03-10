#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"
source "$CURRENT_DIR/profiles.sh"

_get_claude_dir() {
    local dir
    dir=$(get_profile_claude_dir 2>/dev/null)
    [[ -z "$dir" ]] && dir="$HOME/.claude"
    printf '%s' "$dir"
}

_latest_session_file() {
    local claude_dir
    claude_dir=$(_get_claude_dir)
    local projects_dir="$claude_dir/projects"
    [[ ! -d "$projects_dir" ]] && return 1

    local latest="" latest_mtime=0
    local f
    for f in "$projects_dir"/*/*.jsonl "$projects_dir"/*/*/subagents/*.jsonl; do
        [[ -f "$f" ]] || continue
        local mt
        mt=$(get_file_mtime "$f") || continue
        if [[ "$mt" -gt "$latest_mtime" ]]; then
            latest_mtime=$mt
            latest=$f
        fi
    done
    [[ -n "$latest" ]] && printf '%s' "$latest"
}

get_context_usage() {
    local f
    f=$(_latest_session_file) || return 1
    [[ -z "$f" ]] && return 1

    tail -20 "$f" 2>/dev/null | python3 -c "
import sys, json
max_ctx = 0
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        e = json.loads(line)
        if e.get('type') != 'assistant': continue
        u = e.get('message', {}).get('usage', {})
        ctx = u.get('input_tokens', 0) + u.get('cache_read_input_tokens', 0) + u.get('cache_creation_input_tokens', 0)
        if ctx > max_ctx:
            max_ctx = ctx
    except: pass
print(max_ctx)
" 2>/dev/null
}

get_last_model() {
    local f
    f=$(_latest_session_file) || return 1
    [[ -z "$f" ]] && return 1

    tail -20 "$f" 2>/dev/null | python3 -c "
import sys, json
model = ''
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        e = json.loads(line)
        if e.get('type') != 'assistant': continue
        m = e.get('message', {}).get('model', '')
        if m and m != '<synthetic>':
            model = m
    except: pass
if 'opus' in model: print('opus')
elif 'sonnet' in model: print('sonnet')
elif 'haiku' in model: print('haiku')
elif model: print(model)
" 2>/dev/null
}

get_rate_limit_info() {
    local f
    f=$(_latest_session_file) || return 1
    [[ -z "$f" ]] && return 1

    tail -50 "$f" 2>/dev/null | python3 -c "
import sys, json, re
for line in reversed(list(sys.stdin)):
    line = line.strip()
    if not line: continue
    try:
        e = json.loads(line)
        if not e.get('isApiErrorMessage'): continue
        content = ''
        for c in e.get('message', {}).get('content', []):
            content += c.get('text', '')
        if 'resets' in content.lower() or 'rate' in content.lower() or 'limit' in content.lower() or 'cap' in content.lower():
            m = re.search(r'resets?\s+(.*?)$', content, re.I)
            if m:
                print('limited:' + m.group(1).strip())
            else:
                print('limited')
            sys.exit(0)
    except: pass
print('ok')
" 2>/dev/null
}

get_session_count() {
    local count=0
    if [[ "$(get_platform)" == "darwin" ]]; then
        count=$(pgrep -f "claude" 2>/dev/null | wc -l | tr -d ' ')
    else
        count=$(pgrep -f "claude" 2>/dev/null | wc -l | tr -d ' ')
    fi
    printf '%d' "${count:-0}"
}

get_session_memory() {
    if [[ "$(get_platform)" == "darwin" ]]; then
        ps -eo rss,comm 2>/dev/null | awk '/claude/ {sum+=$1} END {printf "%d", sum/1024}'
    else
        ps -eo rss,comm 2>/dev/null | awk '/claude/ {sum+=$1} END {printf "%d", sum/1024}'
    fi
}

_rl_history_file() {
    local cache_dir
    cache_dir="$(get_cache_dir 2>/dev/null)" || return 1
    printf '%s/rate_limits.log' "$cache_dir"
}

record_rate_limit() {
    local rl_file
    rl_file=$(_rl_history_file) || return 1
    local now
    now=$(date +%s)
    printf '%d\n' "$now" >> "$rl_file"
    local cutoff=$(( now - 604800 ))
    local tmp="${rl_file}.tmp"
    awk -v c="$cutoff" '$1 >= c' "$rl_file" > "$tmp" 2>/dev/null && mv -f "$tmp" "$rl_file"
}

get_rate_limit_history() {
    local rl_file
    rl_file=$(_rl_history_file) || { echo "0 0 0"; return; }
    [[ -f "$rl_file" ]] || { echo "0 0 0"; return; }
    local now
    now=$(date +%s)
    local c1h=$(( now - 3600 )) c24h=$(( now - 86400 )) c7d=$(( now - 604800 ))
    awk -v h="$c1h" -v d="$c24h" -v w="$c7d" '
    BEGIN { h1=0; d1=0; w1=0 }
    { if ($1 >= h) h1++; if ($1 >= d) d1++; if ($1 >= w) w1++ }
    END { printf "%d %d %d", h1, d1, w1 }
    ' "$rl_file" 2>/dev/null || echo "0 0 0"
}

get_workspace_vitals() {
    local cpu_pct mem_pct disk_pct
    if [[ "$(get_platform)" == "darwin" ]]; then
        cpu_pct=$(ps -A -o %cpu 2>/dev/null | awk '{s+=$1} END {printf "%d", s/'"$(sysctl -n hw.ncpu 2>/dev/null || echo 1)"'*100/100}' 2>/dev/null || echo 0)
        mem_pct=$(vm_stat 2>/dev/null | python3 -c "
import sys
d = {}
for l in sys.stdin:
    parts = l.strip().rstrip('.').split(':')
    if len(parts)==2:
        try: d[parts[0].strip()] = int(parts[1].strip())
        except: pass
free = d.get('Pages free', 0) + d.get('Pages speculative', 0)
active = d.get('Pages active', 0)
inactive = d.get('Pages inactive', 0)
wired = d.get('Pages wired down', 0)
compressed = d.get('Pages occupied by compressor', 0)
total = free + active + inactive + wired + compressed
used = active + wired + compressed
print(int(used * 100 / total) if total > 0 else 0)
" 2>/dev/null || echo 0)
    else
        cpu_pct=$(awk '{printf "%d", $1*100/'"$(nproc 2>/dev/null || echo 1)"'}' /proc/loadavg 2>/dev/null || echo 0)
        mem_pct=$(awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END {printf "%d", (t-a)*100/t}' /proc/meminfo 2>/dev/null || echo 0)
    fi
    disk_pct=$(df -h / 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); printf "%d", $5}' || echo 0)
    printf '%d %d %d' "$cpu_pct" "$mem_pct" "$disk_pct"
}

write_live_cache() {
    local cache_dir
    cache_dir="$(get_cache_dir 2>/dev/null)" || return 1
    local live_file="${cache_dir}/live.json"

    local context model rate_limit sessions memory
    context=$(get_context_usage 2>/dev/null)
    model=$(get_last_model 2>/dev/null)
    rate_limit=$(get_rate_limit_info 2>/dev/null)
    sessions=$(get_session_count 2>/dev/null)
    memory=$(get_session_memory 2>/dev/null)

    if [[ "${rate_limit:-ok}" != "ok" ]]; then
        record_rate_limit 2>/dev/null
    fi

    local rl_hist
    rl_hist=$(get_rate_limit_history 2>/dev/null)
    local rl_1h rl_24h rl_7d
    read -r rl_1h rl_24h rl_7d <<< "${rl_hist:-0 0 0}"

    local vitals
    vitals=$(get_workspace_vitals 2>/dev/null)
    local cpu mem disk
    read -r cpu mem disk <<< "${vitals:-0 0 0}"

    local now
    now=$(date +%s)

    printf '{"ts":%d,"context":%s,"model":"%s","rate_limit":"%s","sessions":%s,"memory_mb":%s,"rl_1h":%s,"rl_24h":%s,"rl_7d":%s,"cpu":%s,"mem":%s,"disk":%s}\n' \
        "$now" "${context:-0}" "${model:-unknown}" "${rate_limit:-ok}" "${sessions:-0}" "${memory:-0}" \
        "${rl_1h:-0}" "${rl_24h:-0}" "${rl_7d:-0}" "${cpu:-0}" "${mem:-0}" "${disk:-0}" \
        > "$live_file"
}

read_live_cache() {
    local cache_dir
    cache_dir="$(get_cache_dir 2>/dev/null)" || return 1
    local live_file="${cache_dir}/live.json"
    [[ -f "$live_file" ]] || return 1

    local mtime now age
    mtime=$(get_file_mtime "$live_file") || return 1
    now=$(date +%s)
    age=$(( now - mtime ))
    [[ $age -gt 30 ]] && return 1

    cat "$live_file"
}
