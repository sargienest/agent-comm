#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/agent-comm-common.sh
source "${SCRIPT_DIR}/agent-comm-common.sh"

if ! tmux has-session -t "$AC_TMUX_SESSION_NAME" 2>/dev/null; then
    echo "セッション '${AC_TMUX_SESSION_NAME}' は存在しません。"
    exit 0
fi

{
    echo "session: \"${AC_TMUX_SESSION_NAME}\""
    echo "stopped_at: \"$(date -Iseconds)\""
    echo "coordinator: \"stopped\""
    echo "task_author: \"stopped\""
    echo "dispatcher: \"stopped\""
    echo "workers:"
    while IFS= read -r worker_id; do
        echo "  ${worker_id}: \"stopped\""
    done < <(ac_worker_ids)
} > "${STATUS_DIR}/current.yaml"

for pane in $(tmux list-panes -s -t "$AC_TMUX_SESSION_NAME" -F '#{window_name}.#{pane_index}' 2>/dev/null); do
    tmux send-keys -t "$AC_TMUX_SESSION_NAME:$pane" '/exit' C-m 2>/dev/null || true
    sleep 0.2
    tmux send-keys -t "$AC_TMUX_SESSION_NAME:$pane" 'exit' C-m 2>/dev/null || true
done

sleep 2
for pane_pid in $(tmux list-panes -s -t "$AC_TMUX_SESSION_NAME" -F '#{pane_pid}' 2>/dev/null); do
    pkill -TERM -P "$pane_pid" 2>/dev/null || true
done
sleep 1
for pane_pid in $(tmux list-panes -s -t "$AC_TMUX_SESSION_NAME" -F '#{pane_pid}' 2>/dev/null); do
    pkill -KILL -P "$pane_pid" 2>/dev/null || true
done

tmux kill-session -t "$AC_TMUX_SESSION_NAME"
rm -f "$DISPATCHER_PID_FILE" "$DISPATCHER_TOKEN_FILE"
pkill -f "${AC_REPO_ROOT}/scripts/watch-reports.sh" >/dev/null 2>&1 || true

echo "セッション '${AC_TMUX_SESSION_NAME}' を停止しました。"
