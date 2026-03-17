#!/bin/bash
# worker用: ユーザー確認質問を作成し、タスクを blocked へ移す

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/agent-comm-common.sh
source "${SCRIPT_DIR}/agent-comm-common.sh"

usage() {
    cat <<'USAGE'
使い方:
  ./scripts/create-question.sh --task-id <task_id> --question <text>
USAGE
}

TASK_ID=""
QUESTION=""

while [ $# -gt 0 ]; do
    case "$1" in
        --task-id)
            TASK_ID="${2:-}"
            shift 2
            ;;
        --question)
            QUESTION="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "❌ エラー: 不明な引数です: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [ -z "$TASK_ID" ] || [ -z "$QUESTION" ]; then
    usage >&2
    exit 1
fi

ac_assert_task_id "$TASK_ID"
ac_ensure_dirs

if ! task_file=$(ac_find_task_file_by_id "$TASK_ID" 2>/dev/null); then
    echo "❌ エラー: task_id が見つかりません: ${TASK_ID}" >&2
    exit 1
fi

state=$(ac_task_state_from_path "$task_file")
if [ "$state" != "inflight" ]; then
    echo "❌ エラー: inflight タスクのみ質問作成できます（現在: ${state}）" >&2
    exit 1
fi

worker_id=$(ac_read_yaml_scalar "$task_file" "assigned_to")
if [ -z "$worker_id" ]; then
    worker_id="unknown"
fi

max_n=0
for qf in "${QUESTION_OPEN_DIR}/${TASK_ID}_q"*.yaml "${QUESTION_ANSWERED_DIR}/${TASK_ID}_q"*.yaml; do
    [ -f "$qf" ] || continue
    base=$(basename "$qf")
    n=$(echo "$base" | sed -n -E 's/^.*_q([0-9]+)\.yaml$/\1/p')
    if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -gt "$max_n" ]; then
        max_n="$n"
    fi
done

next_n=$((max_n + 1))
question_id="${TASK_ID}_q${next_n}"
question_file="${QUESTION_OPEN_DIR}/${question_id}.yaml"
asked_at=$(ac_now_iso)

{
    echo "id: \"$(ac_escape_yaml_double_quoted "$question_id")\""
    echo "task_id: \"$(ac_escape_yaml_double_quoted "$TASK_ID")\""
    echo "status: \"open\""
    echo "question: |"
    printf '%s\n' "$QUESTION" | sed 's/^/  /'
    echo "answer: |"
    echo "  "
    echo "asked_by: \"$(ac_escape_yaml_double_quoted "$worker_id")\""
    echo "asked_at: \"$(ac_escape_yaml_double_quoted "$asked_at")\""
    echo "answered_by: \"\""
    echo "answered_at: \"\""
} | ac_atomic_write_stdin "$question_file"

ac_set_yaml_scalar "$task_file" "status" "blocked"
ac_set_yaml_scalar "$task_file" "result" "blocked"
ac_set_yaml_scalar "$task_file" "blocked_reason" "question:${question_id}"
ac_set_yaml_scalar "$task_file" "updated_at" "$asked_at"

destination="${TASK_BLOCKED_DIR}/$(basename "$task_file")"
mv "$task_file" "$destination"
ac_release_task_locks "$destination"

echo "✅ 質問を作成しました: ${question_file}"
