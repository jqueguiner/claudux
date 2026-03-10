#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"

_profiles_file() {
    local config_dir
    config_dir="$(get_config_dir)"
    mkdir -p "$config_dir"
    local f="${config_dir}/profiles.json"
    if [[ ! -f "$f" ]]; then
        printf '{"profiles":{},"active":"default"}' > "$f"
    fi
    printf '%s' "$f"
}

_read_profiles() {
    cat "$(_profiles_file)"
}

_write_profiles() {
    local content="$1"
    printf '%s\n' "$content" > "$(_profiles_file)"
}

profile_add() {
    local name="$1"
    local mode="${2:-local}"
    local api_key="${3:-}"
    local claude_dir="${4:-$HOME/.claude}"

    local profiles
    profiles=$(_read_profiles)

    local exists
    exists=$(printf '%s' "$profiles" | jq -r --arg n "$name" '.profiles[$n] // empty')
    if [[ -n "$exists" ]]; then
        echo "Profile '$name' already exists. Remove it first." >&2
        return 1
    fi

    local new_profile
    if [[ "$mode" == "org" ]]; then
        new_profile=$(jq -n --arg mode "$mode" --arg key "$api_key" \
            '{mode: $mode, api_key: $key}')
    else
        new_profile=$(jq -n --arg mode "$mode" --arg dir "$claude_dir" \
            '{mode: $mode, claude_config_dir: $dir}')
    fi

    local updated
    updated=$(printf '%s' "$profiles" | jq --arg n "$name" --argjson p "$new_profile" \
        '.profiles[$n] = $p')

    local count
    count=$(printf '%s' "$updated" | jq '.profiles | length')
    if [[ "$count" -eq 1 ]]; then
        updated=$(printf '%s' "$updated" | jq --arg n "$name" '.active = $n')
    fi

    _write_profiles "$updated"
    echo "Profile '$name' added."
}

profile_remove() {
    local name="$1"
    local profiles
    profiles=$(_read_profiles)

    local exists
    exists=$(printf '%s' "$profiles" | jq -r --arg n "$name" '.profiles[$n] // empty')
    if [[ -z "$exists" ]]; then
        echo "Profile '$name' not found." >&2
        return 1
    fi

    local updated
    updated=$(printf '%s' "$profiles" | jq --arg n "$name" 'del(.profiles[$n])')

    local active
    active=$(printf '%s' "$updated" | jq -r '.active')
    if [[ "$active" == "$name" ]]; then
        local first
        first=$(printf '%s' "$updated" | jq -r '.profiles | keys | first // "default"')
        updated=$(printf '%s' "$updated" | jq --arg n "$first" '.active = $n')
    fi

    _write_profiles "$updated"

    local cache_dir
    cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/claudux/$name"
    rm -rf "$cache_dir"

    local claude_dir
    claude_dir=$(printf '%s' "$exists" | jq -r '.claude_config_dir // empty')
    if [[ -n "$claude_dir" ]]; then
        claude_dir=$(eval printf '%s' "$claude_dir")
        if [[ "$claude_dir" == "$HOME/.claude-claudux/$name" ]]; then
            rm -rf "$claude_dir"
        fi
    fi

    echo "Profile '$name' deleted."
}

profile_list() {
    local profiles
    profiles=$(_read_profiles)
    local active
    active=$(printf '%s' "$profiles" | jq -r '.active')

    printf '%s' "$profiles" | jq -r --arg active "$active" '
        .profiles | to_entries[] |
        (if .key == $active then "* " else "  " end) +
        .key + " (" + .value.mode + ")"
    '
}

profile_switch() {
    local name="$1"
    local profiles
    profiles=$(_read_profiles)

    local exists
    exists=$(printf '%s' "$profiles" | jq -r --arg n "$name" '.profiles[$n] // empty')
    if [[ -z "$exists" ]]; then
        echo "Profile '$name' not found." >&2
        return 1
    fi

    local updated
    updated=$(printf '%s' "$profiles" | jq --arg n "$name" '.active = $n')
    _write_profiles "$updated"

    local base_cache_dir
    base_cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/claudux"
    rm -f "$base_cache_dir/${name}/cache.json"
    rm -f "$base_cache_dir/${name}/plan.txt"

    echo "Switched to profile '$name'."
}

profile_next() {
    local profiles
    profiles=$(_read_profiles)

    local active
    active=$(printf '%s' "$profiles" | jq -r '.active')

    local next
    next=$(printf '%s' "$profiles" | jq -r --arg active "$active" '
        .profiles | keys | . as $keys |
        (index($active) // -1) |
        . + 1 |
        if . >= ($keys | length) then 0 else . end |
        $keys[.]
    ')

    if [[ -z "$next" ]] || [[ "$next" == "null" ]]; then
        return 1
    fi

    local updated
    updated=$(printf '%s' "$profiles" | jq --arg n "$next" '.active = $n')
    _write_profiles "$updated"

    local base_cache_dir
    base_cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/claudux"
    rm -f "$base_cache_dir/${next}/cache.json"
    rm -f "$base_cache_dir/${next}/plan.txt"

    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -x "$script_dir/fetch.sh" ]]; then
        tmux run-shell -b "$script_dir/fetch.sh" 2>/dev/null || true
    fi

    tmux refresh-client -S 2>/dev/null || true
}

get_active_profile_name() {
    local profiles
    profiles=$(_read_profiles)
    printf '%s' "$profiles" | jq -r '.active'
}

get_active_profile() {
    local profiles
    profiles=$(_read_profiles)
    local active
    active=$(printf '%s' "$profiles" | jq -r '.active')
    printf '%s' "$profiles" | jq -r --arg n "$active" '.profiles[$n] // empty'
}

get_profile_cache_dir() {
    local name
    name=$(get_active_profile_name)
    local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/claudux/${name}"
    mkdir -p "$cache_dir"
    printf '%s' "$cache_dir"
}

get_profile_claude_dir() {
    local profile
    profile=$(get_active_profile)
    if [[ -z "$profile" ]]; then
        printf '%s' "$HOME/.claude"
        return
    fi
    local dir
    dir=$(printf '%s' "$profile" | jq -r '.claude_config_dir // empty')
    if [[ -z "$dir" ]]; then
        printf '%s' "$HOME/.claude"
    else
        eval printf '%s' "$dir"
    fi
}

get_profile_mode() {
    local profile
    profile=$(get_active_profile)
    if [[ -z "$profile" ]]; then
        printf 'auto'
        return
    fi
    printf '%s' "$profile" | jq -r '.mode // "auto"'
}


get_profile_api_key() {
    local profile
    profile=$(get_active_profile)
    if [[ -z "$profile" ]]; then
        return 1
    fi
    local key
    key=$(printf '%s' "$profile" | jq -r '.api_key // empty')
    if [[ -n "$key" ]]; then
        printf '%s' "$key"
        return 0
    fi
    return 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        next) profile_next ;;
        switch-silent)
            profile_switch "$2" >/dev/null
            local_cache="${XDG_CACHE_HOME:-$HOME/.cache}/claudux/$2"
            rm -f "$local_cache/cache.json" "$local_cache/plan.txt"
            script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
            [[ -x "$script_dir/fetch.sh" ]] && tmux run-shell -b "$script_dir/fetch.sh" 2>/dev/null || true
            tmux refresh-client -S 2>/dev/null || true
            tmux display-message "claudux: ✓ switched to profile '$2'" 2>/dev/null || true
            ;;
        *) echo "Usage: profiles.sh next|switch-silent <name>" >&2; exit 1 ;;
    esac
fi
