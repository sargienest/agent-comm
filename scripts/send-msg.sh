#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/agent-comm-common.sh
source "${SCRIPT_DIR}/agent-comm-common.sh"

usage() {
    ac_t "usage.send_msg"
}

if [ "$#" -lt 2 ]; then
    usage >&2
    exit 1
fi

TARGET_NAME="$1"
MESSAGE="$2"

ac_ensure_runtime_dirs
TARGET="$(ac_agent_tmux_target "$TARGET_NAME" 2>/dev/null || true)"
[ -n "$TARGET" ] || ac_fail_with_code "invalid_agent" "$(ac_t_format 'send_msg.error.invalid_agent' "target_name=${TARGET_NAME}")"
tmux list-panes -t "$TARGET" >/dev/null 2>&1 || ac_fail_with_code "tmux_target_missing" "$(ac_t_format 'send_msg.error.tmux_target_missing' "target=${TARGET}")"
ac_send_direct_message "$TARGET_NAME" "$MESSAGE"

ac_t_format "send_msg.success.sent" "target_name=${TARGET_NAME}"
