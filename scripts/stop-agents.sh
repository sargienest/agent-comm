#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/agent-comm-common.sh
source "${SCRIPT_DIR}/agent-comm-common.sh"

run_detached_stop() {
    if command -v setsid >/dev/null 2>&1; then
        setsid env AC_STOP_DETACHED=1 bash "$0" >/dev/null 2>&1 < /dev/null &
    else
        nohup env AC_STOP_DETACHED=1 bash "$0" >/dev/null 2>&1 &
    fi
}

yaml_scalar_value() {
    local file_path="$1"
    local key="$2"

    [ -f "$file_path" ] || return 0

    awk -v target_key="$key" '
        $0 ~ "^[[:space:]]*" target_key ":[[:space:]]*" {
            value = $0
            sub(/^[^:]+:[[:space:]]*/, "", value)
            gsub(/^[[:space:]]*"/, "", value)
            gsub(/"[[:space:]]*$/, "", value)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            print value
            exit
        }
    ' "$file_path"
}

tmux_session_exists() {
    local session_name="$1"
    [ -n "$session_name" ] || return 1
    tmux has-session -t "$session_name" 2>/dev/null
}

write_offline_runtime_status() {
    local status_session="$1"

    [ -n "$status_session" ] || status_session="$AC_TMUX_SESSION_NAME"

    {
        echo "session: \"${status_session}\""
        echo "stopped_at: \"$(date -Iseconds)\""
        echo "coordinator: \"offline\""
        echo "task_author: \"offline\""
        echo "dispatcher: \"offline\""
        echo "workers:"
        while IFS= read -r worker_id; do
            echo "  ${worker_id}: \"offline\""
        done < <(ac_worker_ids)
    } > "${STATUS_DIR}/current.yaml"
}

write_tmux_unavailable_snapshots() {
    rm -f "${TMUX_SNAPSHOT_DIR}"/*.yaml 2>/dev/null || true

    ac_capture_tmux_snapshot "coordinator" "${AC_TMUX_SESSION_NAME}:coordinator"
    ac_capture_tmux_snapshot "task_author" "${AC_TMUX_SESSION_NAME}:task-author"
    ac_capture_tmux_snapshot "dispatcher" "${AC_TMUX_SESSION_NAME}:dispatcher"

    while IFS= read -r worker_id; do
        [ -n "$worker_id" ] || continue
        ac_capture_tmux_snapshot "$worker_id" "$(ac_agent_tmux_target "$worker_id")"
    done < <(ac_worker_ids)
}

collect_candidate_sessions() {
    local status_session tmux_target session_name snapshot_file
    local -a candidates=()
    local -A seen=()

    add_candidate() {
        local candidate="$1"
        candidate="${candidate#\"}"
        candidate="${candidate%\"}"
        candidate="$(printf '%s' "$candidate" | tr -d '\r')"
        candidate="${candidate#"${candidate%%[![:space:]]*}"}"
        candidate="${candidate%"${candidate##*[![:space:]]}"}"
        [ -n "$candidate" ] || return 0
        if [ -z "${seen[$candidate]:-}" ]; then
            seen["$candidate"]=1
            candidates+=("$candidate")
        fi
    }

    add_candidate "$AC_TMUX_SESSION_NAME"

    status_session="$(yaml_scalar_value "${STATUS_DIR}/current.yaml" "session" || true)"
    add_candidate "$status_session"

    for snapshot_file in "${TMUX_SNAPSHOT_DIR}"/*.yaml; do
        [ -f "$snapshot_file" ] || continue
        tmux_target="$(yaml_scalar_value "$snapshot_file" "tmux_target" || true)"
        session_name="${tmux_target%%:*}"
        add_candidate "$session_name"
    done

    printf '%s\n' "${candidates[@]}"
}

session_in_list() {
    local needle="$1"
    shift || true

    local entry
    for entry in "$@"; do
        if [ "$entry" = "$needle" ]; then
            return 0
        fi
    done
    return 1
}

kill_session_children() {
    local session_name="$1"
    local pane_pid

    while IFS= read -r pane_pid; do
        [ -n "$pane_pid" ] || continue
        pkill -TERM -P "$pane_pid" 2>/dev/null || true
    done < <(tmux list-panes -s -t "$session_name" -F '#{pane_pid}' 2>/dev/null || true)

    sleep 1

    while IFS= read -r pane_pid; do
        [ -n "$pane_pid" ] || continue
        pkill -KILL -P "$pane_pid" 2>/dev/null || true
    done < <(tmux list-panes -s -t "$session_name" -F '#{pane_pid}' 2>/dev/null || true)
}

stop_tmux_session() {
    local session_name="$1"
    local pane

    while IFS= read -r pane; do
        [ -n "$pane" ] || continue
        tmux send-keys -t "${session_name}:${pane}" '/exit' C-m 2>/dev/null || true
        sleep 0.2
        tmux send-keys -t "${session_name}:${pane}" 'exit' C-m 2>/dev/null || true
    done < <(tmux list-panes -s -t "$session_name" -F '#{window_name}.#{pane_index}' 2>/dev/null || true)

    sleep 2
    kill_session_children "$session_name"

    tmux kill-session -t "$session_name" 2>/dev/null || true
    sleep 0.5
    if tmux_session_exists "$session_name"; then
        kill_session_children "$session_name"
        tmux kill-session -t "$session_name" 2>/dev/null || true
    fi
}

mapfile -t candidate_sessions < <(collect_candidate_sessions)

existing_sessions=()
for session_name in "${candidate_sessions[@]}"; do
    if tmux_session_exists "$session_name"; then
        existing_sessions+=("$session_name")
    fi
done

if [ "${#existing_sessions[@]}" -eq 0 ]; then
    status_session="$(yaml_scalar_value "${STATUS_DIR}/current.yaml" "session" || true)"
    write_offline_runtime_status "$status_session"
    write_tmux_unavailable_snapshots
    rm -f "$DISPATCHER_PID_FILE" "$DISPATCHER_TOKEN_FILE"
    pkill -f "${AC_REPO_ROOT}/scripts/watch-reports.sh" >/dev/null 2>&1 || true
    write_offline_runtime_status "$status_session"
    ac_t_format "stop.session_missing_cleared" "session=${AC_TMUX_SESSION_NAME}"
    exit 0
fi

if [ "${AC_STOP_DETACHED:-0}" != "1" ] && [ -n "${TMUX:-}" ]; then
    current_session="$(tmux display-message -p '#S' 2>/dev/null || true)"
    if session_in_list "$current_session" "${existing_sessions[@]}"; then
        run_detached_stop
        ac_t_format "stop.session_detached_started" "session=${current_session}"
        exit 0
    fi
fi

status_session="${existing_sessions[0]}"
write_offline_runtime_status "$status_session"

for session_name in "${existing_sessions[@]}"; do
    stop_tmux_session "$session_name"
done

rm -f "$DISPATCHER_PID_FILE" "$DISPATCHER_TOKEN_FILE"
pkill -f "${AC_REPO_ROOT}/scripts/watch-reports.sh" >/dev/null 2>&1 || true

remaining_sessions=()
for session_name in "${existing_sessions[@]}"; do
    if tmux_session_exists "$session_name"; then
        remaining_sessions+=("$session_name")
    fi
done

if [ "${#remaining_sessions[@]}" -gt 0 ]; then
    ac_t_format "stop.session_stop_failed" "sessions=$(IFS=', '; echo "${remaining_sessions[*]}")" >&2
    exit 1
fi

write_offline_runtime_status "$status_session"
write_tmux_unavailable_snapshots

ac_t_format "stop.session_stopped" "sessions=$(IFS=', '; echo "${existing_sessions[*]}")"
