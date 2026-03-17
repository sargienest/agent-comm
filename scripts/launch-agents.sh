#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/agent-comm-common.sh
source "${SCRIPT_DIR}/agent-comm-common.sh"

if ! tmux has-session -t "$AC_TMUX_SESSION_NAME" 2>/dev/null; then
    ac_fail "$(ac_t_format 'launch.error.session_missing' "session=${AC_TMUX_SESSION_NAME}")"
fi

while IFS= read -r runtime; do
    [ -n "$runtime" ] || continue
    ac_require_runtime_command "$runtime"
    ac_require_runtime_auth "$runtime"
done < <(ac_required_runtimes)

ac_ensure_role_manifest

common_role="$(ac_role_path common)"
coordinator_role="$(ac_role_path coordinator)"
task_author_role="$(ac_role_path task_author)"

send_plain() {
    local target="$1"
    local message="$2"
    tmux send-keys -t "$target" -l "$message"
    tmux send-keys -t "$target" C-m
}

confirm_workspace_trust() {
    local target="$1"
    sleep 0.3
    tmux send-keys -t "$target" C-m
}

launch_agent_runtime() {
    local agent_id="$1"
    local target launch_command delay_seconds
    target="$(ac_agent_tmux_target "$agent_id")"
    launch_command="$(ac_agent_launch_command "$agent_id")"
    send_plain "$target" "$launch_command"
    confirm_workspace_trust "$target"
    delay_seconds="$(ac_agent_startup_delay_seconds "$agent_id")"
    sleep "$delay_seconds"
}

launch_agent_runtime coordinator
launch_agent_runtime task_author

while IFS= read -r agent_id; do
    [ -n "$agent_id" ] || continue
    launch_agent_runtime "$agent_id"
done < <(ac_worker_ids)

ac_send_direct_message coordinator "${AC_RESET_COMMAND}
$(ac_render_coordinator_boot_message "$common_role" "$coordinator_role")"

ac_send_direct_message task_author "${AC_RESET_COMMAND}
$(ac_render_task_author_boot_message "$common_role" "$task_author_role")"

echo "agents launched"
