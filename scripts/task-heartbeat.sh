#!/bin/bash
# inflight タスクの updated_at を更新する

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/agent-comm-common.sh
source "${SCRIPT_DIR}/agent-comm-common.sh"

if [ "$#" -lt 2 ] || [ "$1" != "--task-id" ]; then
    echo "使い方: ./scripts/task-heartbeat.sh --task-id <task_id>" >&2
    exit 1
fi

TASK_ID="$2"
ac_assert_task_id "$TASK_ID"

ac_ensure_dirs

if ! task_file=$(ac_find_task_file_by_id "$TASK_ID" 2>/dev/null); then
    echo "❌ エラー: task_id が見つかりません: ${TASK_ID}" >&2
    exit 1
fi

state=$(ac_task_state_from_path "$task_file")
if [ "$state" != "inflight" ]; then
    echo "❌ エラー: inflight 以外は heartbeat できません（現在: ${state}）" >&2
    exit 1
fi

ac_set_yaml_scalar "$task_file" "updated_at" "$(ac_now_iso)"

echo "✅ heartbeat 更新: ${TASK_ID}"
