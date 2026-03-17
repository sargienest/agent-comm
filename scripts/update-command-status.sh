#!/bin/bash
# command の status を更新する

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/agent-comm-common.sh
source "${SCRIPT_DIR}/agent-comm-common.sh"

usage() {
    cat <<'USAGE'
使い方:
  ./scripts/update-command-status.sh --status <pending|inflight|done|blocked> [--output <path>]
USAGE
}

STATUS=""
OUTPUT_PATH="${COMMANDS_DIR}/command.yaml"

while [ $# -gt 0 ]; do
    case "$1" in
        --status)
            STATUS="${2:-}"
            shift 2
            ;;
        --output)
            OUTPUT_PATH="${2:-}"
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

case "$STATUS" in
    pending|inflight|done|blocked) ;;
    *)
        echo "❌ エラー: --status は pending|inflight|done|blocked を指定してください。" >&2
        exit 1
        ;;
esac

if [ ! -f "$OUTPUT_PATH" ]; then
    echo "❌ エラー: command ファイルが見つかりません: ${OUTPUT_PATH}" >&2
    exit 1
fi

ac_set_yaml_scalar "$OUTPUT_PATH" "status" "$STATUS"
ac_set_yaml_scalar "$OUTPUT_PATH" "updated_at" "$(ac_now_iso)"

echo "✅ command status を更新しました: ${STATUS}"
