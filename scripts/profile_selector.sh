#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/helpers.sh"
source "$CURRENT_DIR/profiles.sh"

profiles_data=$(_read_profiles)
active=$(printf '%s' "$profiles_data" | jq -r '.active')
keys=$(printf '%s' "$profiles_data" | jq -r '.profiles | keys[]')

[[ -z "$keys" ]] && exit 0

menu_args=(-T " Select Claude Profile " -x C -y C)

i=1
while IFS= read -r name; do
    mode=$(printf '%s' "$profiles_data" | jq -r --arg n "$name" '.profiles[$n].mode // "local"')
    if [[ "$name" == "$active" ]]; then
        label="* ${name} (${mode})"
    else
        label="  ${name} (${mode})"
    fi
    menu_args+=("$label" "$i" "run-shell '${CURRENT_DIR}/profiles.sh switch-silent ${name}'")
    i=$((i + 1))
done <<< "$keys"

tmux display-menu "${menu_args[@]}"
