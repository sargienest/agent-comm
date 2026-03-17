#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/agent-comm-common.sh
source "${SCRIPT_DIR}/agent-comm-common.sh"

if tmux has-session -t "$AC_TMUX_SESSION_NAME" 2>/dev/null; then
    ac_fail "セッション '${AC_TMUX_SESSION_NAME}' は既に存在します。"
fi

ac_ensure_runtime_dirs

if [ -d "$AC_RUNTIME_ROOT" ]; then
    backup_dir="${AC_RUNTIME_ROOT}/backup/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    for path in commands tasks reviews questions rework_notes events reports status; do
        if [ -d "${AC_RUNTIME_ROOT}/${path}" ]; then
            cp -a "${AC_RUNTIME_ROOT}/${path}" "$backup_dir/" 2>/dev/null || true
        fi
    done
fi

find "$COMMANDS_DIR" -maxdepth 1 -type f -name '*.yaml' -delete 2>/dev/null || true
find "$TASK_PENDING_DIR" "$TASK_INFLIGHT_DIR" "$TASK_DONE_DIR" "$TASK_BLOCKED_DIR" -maxdepth 1 -type f -name '*.yaml' -delete 2>/dev/null || true
find "$REVIEW_PENDING_DIR" "$REVIEW_INFLIGHT_DIR" "$REVIEW_DONE_DIR" -maxdepth 1 -type f -name '*.yaml' -delete 2>/dev/null || true
find "$QUESTION_OPEN_DIR" "$QUESTION_ANSWERED_DIR" -maxdepth 1 -type f -name '*.yaml' -delete 2>/dev/null || true
find "$EVENT_OUTBOX_DIR" "$EVENT_SENT_DIR" -maxdepth 1 -type f -name '*.yaml' -delete 2>/dev/null || true
find "$REPORTS_DIR" -maxdepth 1 -type f -name '*_report.yaml' -delete 2>/dev/null || true
find "$REPORT_EVENTS_DIR" -maxdepth 1 -type f -name '*.yaml' -delete 2>/dev/null || true
find "$TMUX_SNAPSHOT_DIR" -maxdepth 1 -type f -name '*.yaml' -delete 2>/dev/null || true
find "$FILE_LOCKS_DIR" -mindepth 1 -maxdepth 1 -type d -name '*.lock' -exec rm -rf {} + 2>/dev/null || true
rm -f "$DISPATCHER_PID_FILE" "$DISPATCHER_TOKEN_FILE"

ac_init_runtime_files

{
    echo "session: \"${AC_TMUX_SESSION_NAME}\""
    echo "started_at: \"$(date -Iseconds)\""
    echo "coordinator: \"idle\""
    echo "task_author: \"idle\""
    echo "dispatcher: \"idle\""
    echo "workers:"
    while IFS= read -r worker_id; do
        [ -n "$worker_id" ] || continue
        echo "  ${worker_id}: \"idle\""
    done < <(ac_worker_ids)
} > "${STATUS_DIR}/current.yaml"

create_single_window() {
    local window_name="$1"
    tmux new-window -t "$AC_TMUX_SESSION_NAME" -n "$window_name" -c "$AC_AGENT_WORKING_DIR"
}

create_pool_window() {
    local window_name="$1"
    local count="$2"
    local pane_index=2

    tmux new-window -t "$AC_TMUX_SESSION_NAME" -n "$window_name" -c "$AC_AGENT_WORKING_DIR"
    while [ "$pane_index" -le "$count" ]; do
        tmux split-window -t "$AC_TMUX_SESSION_NAME:${window_name}" -c "$AC_AGENT_WORKING_DIR"
        pane_index=$((pane_index + 1))
    done
    tmux select-layout -t "$AC_TMUX_SESSION_NAME:${window_name}" tiled
}

reset_target() {
    local target="$1"
    tmux clear-history -t "$target" 2>/dev/null || true
    tmux send-keys -t "$target" 'clear' C-m
}

label_target() {
    local target="$1"
    local label="$2"
    tmux send-keys -t "$target" "echo \"=== ${label} ===\"" C-m
}

tmux new-session -d -s "$AC_TMUX_SESSION_NAME" -n coordinator -c "$AC_AGENT_WORKING_DIR" -x 240 -y 60
tmux set-option -t "$AC_TMUX_SESSION_NAME" destroy-unattached off

create_single_window "task-author"
create_single_window "investigation"
create_single_window "analyst"
create_pool_window "implementer" "${AC_SECTION_COUNT[implementer]}"
create_pool_window "reviewer" "${AC_SECTION_COUNT[reviewer]}"
create_single_window "tester"
create_single_window "dispatcher"

reset_target "${AC_TMUX_SESSION_NAME}:coordinator"
label_target "${AC_TMUX_SESSION_NAME}:coordinator" "coordinator"

reset_target "${AC_TMUX_SESSION_NAME}:task-author"
label_target "${AC_TMUX_SESSION_NAME}:task-author" "task_author"

reset_target "${AC_TMUX_SESSION_NAME}:investigation"
label_target "${AC_TMUX_SESSION_NAME}:investigation" "investigation"

reset_target "${AC_TMUX_SESSION_NAME}:analyst"
label_target "${AC_TMUX_SESSION_NAME}:analyst" "analyst"

reset_target "${AC_TMUX_SESSION_NAME}:tester"
label_target "${AC_TMUX_SESSION_NAME}:tester" "tester"

reset_target "${AC_TMUX_SESSION_NAME}:dispatcher"
label_target "${AC_TMUX_SESSION_NAME}:dispatcher" "dispatcher"

while IFS= read -r agent_id; do
    [ -n "$agent_id" ] || continue
    reset_target "$(ac_agent_tmux_target "$agent_id")"
    label_target "$(ac_agent_tmux_target "$agent_id")" "$agent_id"
done < <(ac_section_agent_ids implementer)

while IFS= read -r agent_id; do
    [ -n "$agent_id" ] || continue
    reset_target "$(ac_agent_tmux_target "$agent_id")"
    label_target "$(ac_agent_tmux_target "$agent_id")" "$agent_id"
done < <(ac_section_agent_ids reviewer)

tmux send-keys -t "$AC_TMUX_SESSION_NAME:dispatcher" "while true; do ${AC_REPO_ROOT}/scripts/watch-reports.sh; code=\$?; echo \"dispatcher stopped (code=\$code)\"; sleep 2; done" C-m

tmux select-window -t "$AC_TMUX_SESSION_NAME:coordinator"

echo "tmux session started: ${AC_TMUX_SESSION_NAME}"
