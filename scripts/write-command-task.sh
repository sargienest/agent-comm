#!/bin/bash
# coordinator -> task_author 指示ファイルを生成する

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/agent-comm-common.sh
source "${SCRIPT_DIR}/agent-comm-common.sh"

usage() {
    ac_t "usage.write_command_task"
}

COMMAND_TEXT=""
COMMAND_ID=""
PRIORITY="high"
OUTPUT_PATH=""

while [ $# -gt 0 ]; do
    case "$1" in
        --command)
            COMMAND_TEXT="${2:-}"
            shift 2
            ;;
        --id)
            COMMAND_ID="${2:-}"
            shift 2
            ;;
        --priority)
            PRIORITY="${2:-}"
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
            ac_t_format "cli.error.unknown_argument" "arg=$1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [ -z "$COMMAND_TEXT" ]; then
    ac_t "write_command_task.error.command_required" >&2
    exit 1
fi

case "$PRIORITY" in
    high|medium|low) ;;
    *)
        ac_t "write_command_task.error.invalid_priority" >&2
        exit 1
        ;;
esac

ac_ensure_dirs

if [ -z "$COMMAND_ID" ]; then
    COMMAND_ID="cmd_$(date '+%Y%m%d_%H%M%S_%N')_${RANDOM}"
fi

if [ -z "$OUTPUT_PATH" ]; then
    OUTPUT_PATH="${COMMANDS_DIR}/command.yaml"
fi

ts=$(date '+%Y-%m-%dT%H:%M:%S.%N%z')
tmp_file=$(mktemp)
trap 'rm -f "$tmp_file"' EXIT

{
    echo "id: \"$(ac_escape_yaml_double_quoted "$COMMAND_ID")\""
    echo "command: |"
    printf '%s\n' "$COMMAND_TEXT" | sed 's/^/  /'
    echo "priority: \"${PRIORITY}\""
    echo "status: \"pending\""
    echo "assigned_to: \"task_author\""
    echo "created_at: \"$(ac_escape_yaml_double_quoted "$ts")\""
    echo "updated_at: \"$(ac_escape_yaml_double_quoted "$ts")\""
} > "$tmp_file"

ac_atomic_write_from_tmp "$tmp_file" "$OUTPUT_PATH"
trap - EXIT

ac_t_format "write_command_task.success.updated" "output_path=${OUTPUT_PATH}"
