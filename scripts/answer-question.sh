#!/bin/bash
# coordinator用: open質問に回答を追記し answered へ移す

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/agent-comm-common.sh
source "${SCRIPT_DIR}/agent-comm-common.sh"

usage() {
    cat <<'USAGE'
使い方:
  ./scripts/answer-question.sh --question-id <task_id_qN> --answer <text>
USAGE
}

QUESTION_ID=""
ANSWER=""

while [ $# -gt 0 ]; do
    case "$1" in
        --question-id)
            QUESTION_ID="${2:-}"
            shift 2
            ;;
        --answer)
            ANSWER="${2:-}"
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

if [ -z "$QUESTION_ID" ] || [ -z "$ANSWER" ]; then
    usage >&2
    exit 1
fi

ac_ensure_dirs

source_file="${QUESTION_OPEN_DIR}/${QUESTION_ID}.yaml"
if [ ! -f "$source_file" ]; then
    echo "❌ エラー: open 質問が見つかりません: ${QUESTION_ID}" >&2
    exit 1
fi

now_iso=$(ac_now_iso)
ac_set_yaml_scalar "$source_file" "status" "answered"
ac_replace_yaml_multiline_block "$source_file" "answer" "$ANSWER"
ac_set_yaml_scalar "$source_file" "answered_by" "coordinator"
ac_set_yaml_scalar "$source_file" "answered_at" "$now_iso"

destination="${QUESTION_ANSWERED_DIR}/$(basename "$source_file")"
mv "$source_file" "$destination"

echo "✅ 質問に回答しました: ${destination}"
