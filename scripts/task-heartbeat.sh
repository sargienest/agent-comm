#!/bin/bash
# inflight タスクの updated_at を更新する

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/agent-comm-common.sh
source "${SCRIPT_DIR}/agent-comm-common.sh"

if [ "$#" -lt 2 ] || [ "$1" != "--task-id" ]; then
    ac_t "usage.task_heartbeat" >&2
    exit 1
fi

TASK_ID="$2"
ac_assert_task_id "$TASK_ID"

ac_ensure_dirs

if ! task_file=$(ac_find_task_file_by_id "$TASK_ID" 2>/dev/null); then
    ac_t_format "task_heartbeat.error.task_not_found" "task_id=${TASK_ID}" >&2
    exit 1
fi

state=$(ac_task_state_from_path "$task_file")
if [ "$state" != "inflight" ]; then
    ac_t_format "task_heartbeat.error.inflight_only" "state=${state}" >&2
    exit 1
fi

ac_set_yaml_scalar "$task_file" "updated_at" "$(ac_now_iso)"

ac_t_format "task_heartbeat.success.updated" "task_id=${TASK_ID}"
