#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/agent-comm-common.sh
source "${SCRIPT_DIR}/agent-comm-common.sh"

if [ $# -lt 1 ]; then
    ac_fail "$(ac_t 'usage.restart_agent')"
fi

if ! tmux has-session -t "$AC_TMUX_SESSION_NAME" 2>/dev/null; then
    ac_fail "$(ac_t_format 'restart_agent.error.session_missing' "session=${AC_TMUX_SESSION_NAME}")"
fi

common_role="$(ac_role_path common)"
coordinator_role="$(ac_role_path coordinator)"
task_author_role="$(ac_role_path task_author)"
worker_role="$(ac_role_path worker)"

kill_pane_children() {
    local target="$1"
    local pane_pid
    pane_pid=$(tmux display-message -t "$target" -p '#{pane_pid}' 2>/dev/null || true)
    if [[ "$pane_pid" =~ ^[0-9]+$ ]]; then
        pkill -TERM -P "$pane_pid" 2>/dev/null || true
        sleep 1
        pkill -KILL -P "$pane_pid" 2>/dev/null || true
    fi
}

reset_pane() {
    local target="$1"
    tmux send-keys -t "$target" '/exit' C-m 2>/dev/null || true
    tmux send-keys -t "$target" 'exit' C-m 2>/dev/null || true
    sleep 1
    kill_pane_children "$target"
    tmux send-keys -t "$target" 'clear' C-m
}

start_dispatcher() {
    local target="$1"
    reset_pane "$target"
    tmux send-keys -t "$target" "while true; do ${AC_REPO_ROOT}/scripts/watch-reports.sh; code=\$?; echo \"dispatcher stopped (code=\$code)\"; sleep 2; done" C-m
}

start_agent_runtime() {
    local agent_id="$1"
    local target launch_command delay_seconds runtime
    target="$(ac_agent_tmux_target "$agent_id")"
    runtime="$(ac_agent_runtime "$agent_id")"
    ac_require_runtime_command "$runtime"
    ac_require_runtime_auth "$runtime"
    reset_pane "$target"
    launch_command="$(ac_agent_launch_command "$agent_id")"
    tmux send-keys -t "$target" -l "$launch_command"
    tmux send-keys -t "$target" C-m
    delay_seconds="$(ac_agent_startup_delay_seconds "$agent_id")"
    sleep "$delay_seconds"
}

restart_singleton_worker() {
    local agent_id="$1"
    ac_validate_worker_id "$agent_id"
    start_agent_runtime "$agent_id"
    ac_send_direct_message "$agent_id" "${AC_RESET_COMMAND}
$(ac_render_worker_boot_message "$agent_id" "$worker_role" "$(ac_role_path "$(ac_worker_persona "$agent_id")")" "$common_role")"
}

restart_coordinator() {
    start_agent_runtime coordinator
    ac_send_direct_message coordinator "${AC_RESET_COMMAND}
$(ac_render_coordinator_boot_message "$common_role" "$coordinator_role")"
}

restart_task_author() {
    start_agent_runtime task_author
    ac_send_direct_message task_author "${AC_RESET_COMMAND}
$(ac_render_task_author_boot_message "$common_role" "$task_author_role")"
}

restart_section_workers() {
    local section="$1"
    local agent_id
    while IFS= read -r agent_id; do
        [ -n "$agent_id" ] || continue
        restart_singleton_worker "$agent_id"
    done < <(ac_section_agent_ids "$section")
}

case "$1" in
    coordinator)
        restart_coordinator
        ;;
    task_author|manager)
        restart_task_author
        ;;
    dispatcher)
        start_dispatcher "${AC_TMUX_SESSION_NAME}:dispatcher"
        ;;
    investigation|analyst|tester)
        restart_singleton_worker "$1"
        ;;
    implementers)
        restart_section_workers implementer
        ;;
    reviewers)
        restart_section_workers reviewer
        ;;
    workers)
        restart_section_workers investigation
        restart_section_workers analyst
        restart_section_workers tester
        restart_section_workers implementer
        restart_section_workers reviewer
        ;;
    implementer*|reviewer*)
        restart_singleton_worker "$1"
        ;;
    all)
        restart_coordinator
        restart_task_author
        restart_section_workers investigation
        restart_section_workers analyst
        restart_section_workers tester
        restart_section_workers implementer
        restart_section_workers reviewer
        start_dispatcher "${AC_TMUX_SESSION_NAME}:dispatcher"
        ;;
    *)
        ac_fail "$(ac_t_format 'restart_agent.error.invalid_target' "target=$1")"
        ;;
esac

echo "restart complete: $1"
